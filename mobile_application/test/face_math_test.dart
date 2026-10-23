import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/face_math.dart';

/// Fixtures were written by the server's own face code (see the scratch generator): the Dart port must reproduce them.
const _dir = 'test/fixtures/face';

dynamic _json(String name) => jsonDecode(File('$_dir/$name').readAsStringSync());
Uint8List _bytes(String name) => File('$_dir/$name').readAsBytesSync();

Float32List _floats(List<dynamic> v) => Float32List.fromList([for (final x in v) (x as num).toDouble()]);

void main() {
  group('YuNet decoding and non-maximum suppression', () {
    for (final i in [0, 1]) {
      test('frame $i: finds the same faces as the server\'s decoder, to a fraction of a pixel', () {
        final meta = _json('yunet_expected_$i.json') as Map<String, dynamic>;
        final names = (meta['names'] as List).cast<String>();
        final shapes = (meta['shapes'] as List).map((s) => (s as List).cast<int>()).toList();
        final blob = _bytes('yunet_raw_$i.bin').buffer.asFloat32List();
        final out = <String, Float32List>{};
        var at = 0;
        for (var k = 0; k < names.length; k++) {
          final n = shapes[k].reduce((a, b) => a * b);
          out[names[k]] = Float32List.sublistView(blob, at, at + n);
          at += n;
        }
        final groups = [
          for (final s in [8, 16, 32]) YuNetStride(stride: s, cls: out['cls_$s']!, obj: out['obj_$s']!, bbox: out['bbox_$s']!, kps: out['kps_$s']!),
        ];
        final faces = decodeYuNet(groups);
        final expected = (meta['detections'] as List).map((d) => (d as List).map((x) => (x as num).toDouble()).toList()).toList();
        expect(expected, isNotEmpty);
        expect(faces.length, expected.length);
        for (var k = 0; k < expected.length; k++) {
          final e = expected[k];
          final f = faces[k];
          expect(f.x, closeTo(e[0], 0.01));
          expect(f.y, closeTo(e[1], 0.01));
          expect(f.w, closeTo(e[2], 0.01));
          expect(f.h, closeTo(e[3], 0.01));
          for (var p = 0; p < 10; p++) {
            expect(f.points[p], closeTo(e[4 + p], 0.01));
          }
          expect(f.score, closeTo(e[14], 1e-4));
        }
      });
    }

    test('two boxes on the same face are reduced to the stronger one, a separate face is kept', () {
      Float32List one(List<double> v) => Float32List.fromList(v);
      // a 32-px grid of 2x2 cells (stride 32, size 64): two overlapping boxes in the left cells, one in the right column
      final g = YuNetStride(
        stride: 32,
        cls: one([0.9, 0.8, 0.0, 0.95]),
        obj: one([0.9, 0.8, 0.0, 0.95]),
        bbox: one([0.5, 0.5, 0, 0, -0.45, 0.5, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0, 0]), // cell 1's box is pulled back onto cell 0's
        kps: Float32List(40),
      );
      final faces = decodeYuNet([g], size: 64);
      expect(faces.length, 2);
      expect(faces.first.score, closeTo(0.95, 1e-6)); // sorted strongest first
    });
  });

  group('aligning a face', () {
    test('reproduces OpenCV\'s robust (LMEDS) similarity for 60 real sets of 5 points, outliers included', () {
      final j = _json('alignment.json') as Map<String, dynamic>;
      final template = (j['template'] as List).map((x) => (x as num).toDouble()).toList();
      for (var i = 0; i < template.length; i++) {
        expect(faceTemplate[i], closeTo(template[i], 1e-4));
      }
      var worst = 0.0;
      for (final c in (j['cases'] as List)) {
        final pts = (c['points'] as List).map((x) => (x as num).toDouble()).toList();
        final m = (c['m'] as List).map((x) => (x as num).toDouble()).toList(); // [a, -b, tx, b, a, ty]
        final got = estimateSimilarity(pts, faceTemplate)!;
        final diff = [(got[0] - m[0]).abs(), (got[1] - m[3]).abs(), (got[2] - m[2]).abs(), (got[3] - m[5]).abs()].reduce(math.max);
        worst = math.max(worst, diff);
      }
      expect(worst, lessThan(0.02), reason: 'worst difference in any matrix entry: $worst');
    });

    test('with two points it is exact, and with too few it says it cannot', () {
      final m = estimateSimilarity([0, 0, 10, 0], [5, 5, 25, 5])!; // scale 2, no rotation, shift (5,5)
      expect(m[0], closeTo(2, 1e-9));
      expect(m[1], closeTo(0, 1e-9));
      expect(m[2], closeTo(5, 1e-9));
      expect(m[3], closeTo(5, 1e-9));
      expect(estimateSimilarity([1, 2], [3, 4]), isNull);
    });

    test('warping matches cv2.warpAffine (bilinear, edges repeated), including parts outside the picture', () {
      final meta = _json('warp.json') as Map<String, dynamic>;
      final w = meta['w'] as int, h = meta['h'] as int;
      final m = (meta['m'] as List).map((x) => (x as num).toDouble()).toList(); // [a, -b, tx, b, a, ty]
      final got = warpToFace(_bytes('warp_in_bgr.bin'), w, h, [m[0], m[3], m[2], m[5]]);
      final want = _bytes('warp_out_bgr.bin');
      expect(got.length, want.length);
      var sum = 0, worst = 0;
      for (var i = 0; i < want.length; i++) {
        final d = (got[i] - want[i]).abs();
        sum += d;
        worst = math.max(worst, d);
      }
      expect(sum / want.length, lessThan(0.6), reason: 'mean absolute difference');
      expect(worst, lessThanOrEqualTo(6), reason: 'worst single value');
    });

    test('the network input is RGB, scaled, normalised and channels first', () {
      final crop = Uint8List(faceInput * faceInput * 3);
      crop[0] = 10; // B of pixel 0
      crop[1] = 20; // G
      crop[2] = 30; // R
      final x = b0Input(crop);
      const plane = faceInput * faceInput;
      expect(x.length, 3 * plane);
      expect(x[0], closeTo((30 / 255 - 0.485) / 0.229, 1e-5));
      expect(x[plane], closeTo((20 / 255 - 0.456) / 0.224, 1e-5));
      expect(x[2 * plane], closeTo((10 / 255 - 0.406) / 0.225, 1e-5));
    });
  });

  group('choosing and following a face', () {
    Detection face(double x, double y, double w, double h) => Detection(x, y, w, h, List.filled(10, 0), 0.9);

    test('picks the big, central face and keeps it when it moves a little', () {
      final t = FaceTracker();
      final big = face(200, 100, 200, 240), small = face(10, 10, 50, 60);
      final first = t.update([small, big], 640, 480);
      expect(first.face, same(big));
      expect(first.found && !first.tracked, isTrue);
      final moved = face(204, 102, 200, 240);
      expect(t.update([small, moved], 640, 480).face, same(moved));
    });

    test('a miss is bridged by the last face for two frames, then it lets go', () {
      final t = FaceTracker();
      final f = face(200, 100, 200, 240);
      t.update([f], 640, 480);
      final a = t.update([], 640, 480);
      expect(a.face, same(f));
      expect(a.tracked, isTrue);
      expect(t.update([], 640, 480).tracked, isTrue);
      final c = t.update([], 640, 480);
      expect(c.face, isNull);
      expect(c.tracked, isFalse);
    });

    test('nothing to bridge before the first face', () {
      expect(FaceTracker().update([], 640, 480).face, isNull);
    });
  });

  group('is the frame good enough to read', () {
    bool usable({bool tracked = false, bool ok = true, double h = 200, double yaw = 0, double pitch = 0}) =>
        frameUsable(tracked: tracked, mediaPipeOk: ok, faceHeight: h, yaw: yaw, pitch: pitch);

    test('follows the server\'s rule', () {
      expect(usable(), isTrue);
      expect(usable(tracked: true), isFalse);
      expect(usable(ok: false), isFalse);
      expect(usable(h: 63), isFalse);
      expect(usable(h: 64), isTrue);
      expect(usable(yaw: 46), isFalse);
      expect(usable(yaw: -45), isTrue);
      expect(usable(pitch: 36), isFalse);
    });

    test('the margin crop around a face stays inside the picture', () {
      final c = landmarkCrop(const Detection(10, 10, 100, 120, [], 1), 640, 480);
      expect(c.x0, 0);
      expect(c.y0, 0);
      expect(c.x1, lessThanOrEqualTo(640));
      expect(c.y1, lessThanOrEqualTo(480));
      final mid = landmarkCrop(const Detection(300, 200, 100, 100, [], 1), 640, 480); // centre (350,250), side 150
      expect([mid.x0, mid.y0, mid.x1, mid.y1], [275, 175, 425, 325]);
    });
  });

  group('head pose', () {
    test('matches the server for 25 rotations with scale and shift', () {
      for (final c in (_json('euler.json') as List)) {
        final m = (c['m'] as List).map((x) => (x as num).toDouble()).toList();
        final p = headPose(m);
        expect(p.yaw, closeTo((c['yaw'] as num).toDouble(), 1e-6));
        expect(p.pitch, closeTo((c['pitch'] as num).toDouble(), 1e-6));
        expect(p.roll, closeTo((c['roll'] as num).toDouble(), 1e-6));
      }
    });
  });

  group('the 1,400-number face vector', () {
    test('matches the server\'s pooled vector (mean/spread of scores and expressions, mean embedding)', () {
      for (final c in (_json('pool.json') as List)) {
        final frames = [
          for (final f in c['frames'] as List)
            FaceFrame(usable: f['usable'] == 1, logits: _floats(f['logits']), blendshapes: _floats(f['bs']), embedding: _floats(f['emb'])),
        ];
        final want = (c['vector'] as List).map((x) => (x as num).toDouble()).toList();
        final got = poolFace(frames)!;
        expect(got.length, faceVectorLength);
        var worstFirst = 0.0, worstEmb = 0.0;
        for (var i = 0; i < faceVectorLength; i++) {
          final d = (got[i] - want[i]).abs();
          if (i < 120) {
            worstFirst = math.max(worstFirst, d);
          } else {
            worstEmb = math.max(worstEmb, d);
          }
        }
        expect(worstFirst, lessThan(1e-5));
        expect(worstEmb, lessThan(1e-3), reason: 'the server rounds embeddings to half precision before averaging');
      }
    });

    test('needs at least 3 usable frames', () {
      FaceFrame f(bool usable) => FaceFrame(usable: usable, logits: Float32List(8), blendshapes: Float32List(52), embedding: Float32List(1280));
      expect(poolFace([f(true), f(true), f(false)]), isNull);
      expect(poolFace([f(true), f(true), f(true)]), isNotNull);
      expect(poolFace([]), isNull);
    });
  });
}
