import 'dart:math' as math;
import 'dart:typed_data';

/// The maths of reading a face, in plain Dart, ported from the server's face pipeline (YuNet + 5-point alignment +
/// EfficientNet-B0 + MediaPipe, pooled into one 1,400-number vector). Only the three neural networks run natively; all of
/// this is checked against the server's own code by the tests in `test/face_math_test.dart`.

const int faceInput = 224;

/// The 5-point alignment template (right eye, left eye, nose, mouth corners as YuNet orders them), as the server uses it.
final List<double> faceTemplate = () {
  const base = [38.29, 51.70, 73.53, 51.50, 56.03, 71.74, 41.55, 92.37, 70.73, 92.20];
  return [for (final v in base) (v * 2 - 112) * 0.85 + 112];
}();

// ---------------------------------------------------------------------------------------------- YuNet: decode + NMS

class Detection {
  const Detection(this.x, this.y, this.w, this.h, this.points, this.score);

  final double x, y, w, h;

  /// 5 points as x0,y0,x1,y1,...
  final List<double> points;
  final double score;
}

/// One YuNet output group for a stride (8, 16 or 32).
class YuNetStride {
  const YuNetStride({required this.stride, required this.cls, required this.obj, required this.bbox, required this.kps});

  final int stride;
  final Float32List cls; // [N]
  final Float32List obj; // [N]
  final Float32List bbox; // [N*4]
  final Float32List kps; // [N*10]
}

double iouXywh(double ax, double ay, double aw, double ah, double bx, double by, double bw, double bh) {
  final iw = math.max(0.0, math.min(ax + aw, bx + bw) - math.max(ax, bx));
  final ih = math.max(0.0, math.min(ay + ah, by + bh) - math.max(ay, by));
  final inter = iw * ih;
  return inter / (aw * ah + bw * bh - inter + 1e-9);
}

/// Decodes YuNet's three output groups for a [size] x [size] input (zero-padded frame) into faces, like OpenCV's
/// FaceDetectorYN: score = sqrt(cls*obj), boxes and 5 points from the grid, then greedy non-maximum suppression.
List<Detection> decodeYuNet(List<YuNetStride> groups, {int size = 640, double scoreThreshold = 0.6, double nmsThreshold = 0.3}) {
  final all = <Detection>[];
  for (final g in groups) {
    final cols = size ~/ g.stride;
    final n = g.cls.length;
    for (var idx = 0; idx < n; idx++) {
      final c = g.cls[idx].clamp(0.0, 1.0);
      final o = g.obj[idx].clamp(0.0, 1.0);
      final score = math.sqrt(c * o);
      if (score < scoreThreshold) continue;
      final r = idx ~/ cols;
      final col = idx % cols;
      final cx = (col + g.bbox[idx * 4]) * g.stride;
      final cy = (r + g.bbox[idx * 4 + 1]) * g.stride;
      final bw = math.exp(g.bbox[idx * 4 + 2]) * g.stride;
      final bh = math.exp(g.bbox[idx * 4 + 3]) * g.stride;
      final pts = <double>[
        for (var j = 0; j < 10; j++) ((j.isEven ? col : r) + g.kps[idx * 10 + j]) * g.stride,
      ];
      all.add(Detection(cx - bw / 2, cy - bh / 2, bw, bh, pts, score));
    }
  }
  all.sort((a, b) => b.score.compareTo(a.score));
  final kept = <Detection>[];
  for (final d in all) {
    var keep = true;
    for (final k in kept) {
      if (iouXywh(d.x, d.y, d.w, d.h, k.x, k.y, k.w, k.h) > nmsThreshold) {
        keep = false;
        break;
      }
    }
    if (keep) kept.add(d);
    if (kept.length >= 5000) break;
  }
  return kept;
}

// ---------------------------------------------------------------------------------------------- face choice + tracking

/// Which face to read in each frame, and bridging a miss for up to 2 frames with the last face (marked tracked).
class FaceTracker {
  Detection? _prev;
  int _miss = 99;

  void reset() {
    _prev = null;
    _miss = 99;
  }

  ({Detection? face, bool found, bool tracked}) update(List<Detection> faces, int width, int height) {
    if (faces.isNotEmpty) {
      double key(Detection f) {
        final cen = 1 - 0.5 * math.sqrt(math.pow((f.x + f.w / 2) / width - 0.5, 2) + math.pow((f.y + f.h / 2) / height - 0.5, 2));
        final p = _prev;
        return f.w * f.h * (0.5 + (p == null ? 0.5 : iouXywh(p.x, p.y, p.w, p.h, f.x, f.y, f.w, f.h))) * cen;
      }

      var best = faces.first;
      var bestKey = key(best);
      for (final f in faces.skip(1)) {
        final k = key(f);
        if (k > bestKey) {
          best = f;
          bestKey = k;
        }
      }
      _prev = best;
      _miss = 0;
      return (face: best, found: true, tracked: false);
    }
    final p = _prev;
    if (p != null && _miss < 2) {
      _miss++;
      return (face: p, found: false, tracked: true);
    }
    _miss++;
    return (face: null, found: false, tracked: false);
  }
}

// ---------------------------------------------------------------------------------------------- alignment

/// A 2x3 similarity matrix [a, -b, tx; b, a, ty] stored as [a, b, tx, ty].
typedef Similarity = List<double>;

Similarity _similarityFromTwo(List<double> s, List<double> d, int i, int j) {
  final sx = s[j * 2] - s[i * 2], sy = s[j * 2 + 1] - s[i * 2 + 1];
  final dx = d[j * 2] - d[i * 2], dy = d[j * 2 + 1] - d[i * 2 + 1];
  final den = sx * sx + sy * sy;
  if (den < 1e-12) return [1, 0, 0, 0];
  final a = (sx * dx + sy * dy) / den;
  final b = (sx * dy - sy * dx) / den;
  final tx = d[i * 2] - (a * s[i * 2] - b * s[i * 2 + 1]);
  final ty = d[i * 2 + 1] - (b * s[i * 2] + a * s[i * 2 + 1]);
  return [a, b, tx, ty];
}

List<double> _squaredErrors(Similarity m, List<double> s, List<double> d) {
  final n = s.length ~/ 2;
  return [
    for (var i = 0; i < n; i++)
      math.pow(m[0] * s[i * 2] - m[1] * s[i * 2 + 1] + m[2] - d[i * 2], 2).toDouble() +
          math.pow(m[1] * s[i * 2] + m[0] * s[i * 2 + 1] + m[3] - d[i * 2 + 1], 2).toDouble(),
  ];
}

Similarity _leastSquares(List<double> s, List<double> d, List<int> use) {
  var smx = 0.0, smy = 0.0, dmx = 0.0, dmy = 0.0;
  for (final i in use) {
    smx += s[i * 2];
    smy += s[i * 2 + 1];
    dmx += d[i * 2];
    dmy += d[i * 2 + 1];
  }
  final n = use.length;
  smx /= n;
  smy /= n;
  dmx /= n;
  dmy /= n;
  var num1 = 0.0, num2 = 0.0, den = 0.0;
  for (final i in use) {
    final px = s[i * 2] - smx, py = s[i * 2 + 1] - smy;
    final qx = d[i * 2] - dmx, qy = d[i * 2 + 1] - dmy;
    num1 += px * qx + py * qy;
    num2 += px * qy - py * qx;
    den += px * px + py * py;
  }
  final a = num1 / den, b = num2 / den;
  return [a, b, dmx - (a * smx - b * smy), dmy - (b * smx + a * smy)];
}

/// OpenCV's estimateAffinePartial2D(method: LMEDS) for a handful of points: every pair of points gives a candidate
/// similarity, the one with the smallest MEDIAN squared error wins, points far from it are dropped as outliers, and the
/// rest are refitted by least squares. Returns [a, b, tx, ty] mapping [src] to [dst], or null when it cannot be solved.
Similarity? estimateSimilarity(List<double> src, List<double> dst) {
  final n = src.length ~/ 2;
  if (n < 2) return null;
  if (n == 2) return _similarityFromTwo(src, dst, 0, 1);
  Similarity? best;
  var bestMedian = double.infinity;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final m = _similarityFromTwo(src, dst, i, j);
      final err = _squaredErrors(m, src, dst)..sort();
      final median = err[n ~/ 2];
      if (median < bestMedian) {
        bestMedian = median;
        best = m;
      }
    }
  }
  if (best == null) return null;
  final errors = _squaredErrors(best, src, dst);
  final sigma = math.max(2.5 * 1.4826 * (1 + 5.0 / (n - 2)) * math.sqrt(bestMedian), 1.1920929e-7);
  // OpenCV compares the plain (not squared) distance with sigma here, which is what makes it keep all five points
  // unless one is clearly off.
  final inliers = [for (var i = 0; i < n; i++) if (math.sqrt(errors[i]) <= sigma) i];
  if (inliers.length < 3) return best;
  return _leastSquares(src, dst, inliers);
}

/// Warps a BGR image into the [faceInput] x [faceInput] aligned crop (bilinear, edges repeated), like cv2.warpAffine
/// with [m] mapping the source to the crop. Returns BGR bytes.
Uint8List warpToFace(Uint8List bgr, int width, int height, Similarity m) {
  final a = m[0], b = m[1], tx = m[2], ty = m[3];
  final det = a * a + b * b;
  final out = Uint8List(faceInput * faceInput * 3);
  // inverse of [a -b; b a] is [a b; -b a] / det
  for (var y = 0; y < faceInput; y++) {
    for (var x = 0; x < faceInput; x++) {
      final px = x - tx, py = y - ty;
      final sx = (a * px + b * py) / det;
      final sy = (-b * px + a * py) / det;
      final x0f = sx.floorToDouble(), y0f = sy.floorToDouble();
      final fx = sx - x0f, fy = sy - y0f;
      final x0 = x0f.toInt(), y0 = y0f.toInt();
      final xa = x0.clamp(0, width - 1), xb = (x0 + 1).clamp(0, width - 1);
      final ya = y0.clamp(0, height - 1), yb = (y0 + 1).clamp(0, height - 1);
      final o = (y * faceInput + x) * 3;
      for (var ch = 0; ch < 3; ch++) {
        final v00 = bgr[(ya * width + xa) * 3 + ch];
        final v01 = bgr[(ya * width + xb) * 3 + ch];
        final v10 = bgr[(yb * width + xa) * 3 + ch];
        final v11 = bgr[(yb * width + xb) * 3 + ch];
        final top = v00 + (v01 - v00) * fx;
        final bottom = v10 + (v11 - v10) * fx;
        out[o + ch] = (top + (bottom - top) * fy).round().clamp(0, 255);
      }
    }
  }
  return out;
}

/// The aligned BGR crop as the B0 network's input: RGB, scaled to 0..1, ImageNet mean and deviation, channels first.
Float32List b0Input(Uint8List bgrCrop) {
  const mean = [0.485, 0.456, 0.406], sd = [0.229, 0.224, 0.225];
  const plane = faceInput * faceInput;
  final out = Float32List(3 * plane);
  for (var i = 0; i < plane; i++) {
    final b = bgrCrop[i * 3], g = bgrCrop[i * 3 + 1], r = bgrCrop[i * 3 + 2];
    out[i] = (r / 255.0 - mean[0]) / sd[0];
    out[plane + i] = (g / 255.0 - mean[1]) / sd[1];
    out[2 * plane + i] = (b / 255.0 - mean[2]) / sd[2];
  }
  return out;
}

/// The square, 1.5x margin crop around a face that MediaPipe reads: [x0, y0, x1, y1] in whole pixels.
({int x0, int y0, int x1, int y1}) landmarkCrop(Detection face, int width, int height) {
  final cx = face.x + face.w / 2, cy = face.y + face.h / 2;
  final s = math.max(face.w, face.h) * 1.5;
  return (
    x0: math.max(0.0, cx - s / 2).toInt(),
    y0: math.max(0.0, cy - s / 2).toInt(),
    x1: math.min(width.toDouble(), cx + s / 2).toInt(),
    y1: math.min(height.toDouble(), cy + s / 2).toInt(),
  );
}

/// Yaw, pitch, roll in degrees from MediaPipe's 4x4 facial transformation matrix (row-major list of 16).
({double yaw, double pitch, double roll}) headPose(List<double> m) {
  // upper-left 3x3, each COLUMN normalised
  final r = [for (var i = 0; i < 3; i++) [for (var j = 0; j < 3; j++) m[i * 4 + j]]];
  for (var j = 0; j < 3; j++) {
    final norm = math.sqrt(r[0][j] * r[0][j] + r[1][j] * r[1][j] + r[2][j] * r[2][j]);
    for (var i = 0; i < 3; i++) {
      r[i][j] /= norm;
    }
  }
  const deg = 180 / math.pi;
  final pitch = math.asin((-r[1][2]).clamp(-1.0, 1.0)) * deg;
  final yaw = math.atan2(r[0][2], r[2][2]) * deg;
  final roll = math.atan2(r[1][0], r[1][1]) * deg;
  return (yaw: yaw, pitch: pitch, roll: roll);
}

/// Is this frame good enough to read? The server's rule: a real (not carried-over) detection, MediaPipe succeeded, the
/// face is at least [minHeight] px tall and not turned too far.
bool frameUsable({required bool tracked, required bool mediaPipeOk, required double faceHeight, required double yaw, required double pitch, double minHeight = 64}) {
  return !tracked && mediaPipeOk && faceHeight >= minHeight && yaw.abs() <= 45 && pitch.abs() <= 35;
}

// ---------------------------------------------------------------------------------------------- pooling

/// What the networks said about one frame.
class FaceFrame {
  const FaceFrame({required this.usable, required this.logits, required this.blendshapes, required this.embedding});

  final bool usable;
  final Float32List logits; // 8
  final Float32List blendshapes; // 52
  final Float32List embedding; // 1280
}

const int faceVectorLength = 1400;
const int minUsableFrames = 3;

/// The 1,400-number face vector the emotion model reads: B0 scores (mean, spread), expression values (mean, spread) and
/// the mean B0 embedding, over the usable frames. Null when fewer than [minUsableFrames] frames are usable.
Float32List? poolFace(List<FaceFrame> frames) {
  final us = [for (final f in frames) if (f.usable) f];
  if (us.length < minUsableFrames) return null;
  final out = Float32List(faceVectorLength);
  void meanStd(int offset, int length, Float32List Function(FaceFrame) pick, {required bool withStd}) {
    for (var k = 0; k < length; k++) {
      var sum = 0.0;
      for (final f in us) {
        sum += pick(f)[k];
      }
      final mean = sum / us.length;
      out[offset + k] = mean;
      if (withStd) {
        var sq = 0.0;
        for (final f in us) {
          final d = pick(f)[k] - mean;
          sq += d * d;
        }
        out[offset + length + k] = math.sqrt(sq / us.length); // population deviation, as numpy's std
      }
    }
  }

  meanStd(0, 8, (f) => f.logits, withStd: true); // 0..15
  meanStd(16, 52, (f) => f.blendshapes, withStd: true); // 16..119
  meanStd(120, 1280, (f) => f.embedding, withStd: false); // 120..1399
  return out;
}
