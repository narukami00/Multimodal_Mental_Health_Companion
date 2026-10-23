import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'face_math.dart';

/// The three neural networks (and picture decoding), natively. Replaceable so the wiring can be tested without a phone.
abstract class FaceModelRunner {
  Future<bool> load(String directory);
  Future<bool> isLoaded();
  Future<void> close();

  /// A JPEG to raw BGR bytes.
  Future<({int w, int h, Uint8List bgr})?> decode(Uint8List jpeg);

  /// YuNet on a zero-padded 640x640 BGR frame: its output groups by name (cls_8 ... kps_32), each flattened.
  Future<Map<String, Float32List>?> yunet(Uint8List paddedBgr);

  /// EfficientNet-B0 on the aligned crop's network input: 8 scores then the 1,280-number embedding.
  Future<Float32List?> b0(Float32List input);

  /// MediaPipe's face landmarker on an RGB crop: [1, 52 expression values, 16 matrix numbers], or null without a face.
  Future<Float32List?> landmarks(Uint8List rgb, int w, int h);
}

/// The real thing: the Kotlin side of the `face_models` channel (see FaceModels.kt).
class ChannelFaceModelRunner implements FaceModelRunner {
  ChannelFaceModelRunner({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('com.sysmentalhealth.solace_mobile/face_models');

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      debugPrint('[FaceReader] $method failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<bool> load(String directory) async => (await _call<bool>('load', {'dir': directory})) ?? false;

  @override
  Future<bool> isLoaded() async => (await _call<bool>('isLoaded')) ?? false;

  @override
  Future<void> close() async => _call<bool>('close');

  @override
  Future<({int w, int h, Uint8List bgr})?> decode(Uint8List jpeg) async {
    final m = await _call<Map<Object?, Object?>>('decode', {'jpeg': jpeg});
    if (m == null) return null;
    return (w: m['w']! as int, h: m['h']! as int, bgr: m['bgr']! as Uint8List);
  }

  @override
  Future<Map<String, Float32List>?> yunet(Uint8List paddedBgr) async {
    final m = await _call<Map<Object?, Object?>>('yunet', {'bgr': paddedBgr});
    return m?.map((k, v) => MapEntry(k! as String, v! as Float32List));
  }

  @override
  Future<Float32List?> b0(Float32List input) => _call<Float32List>('b0', {'input': input});

  @override
  Future<Float32List?> landmarks(Uint8List rgb, int w, int h) => _call<Float32List>('landmarks', {'rgb': rgb, 'w': w, 'h': h});
}

/// Testing only (build with `--dart-define=SOLACE_FACE_COMPARE=true`): a video journal read on the phone ALSO sends its
/// frames to the companion server, whose log then says how close the phone's numbers are to its own. Never on in a normal
/// build: it would defeat the point of keeping the pictures on the phone.
const bool kFaceCompareWithServer = bool.fromEnvironment('SOLACE_FACE_COMPARE');

/// What one camera frame came to.
class FaceReading {
  const FaceReading({required this.found, required this.usable});

  /// A face was found in this frame (or carried over from the last one for a moment).
  final bool found;

  /// The frame was good enough to count: a real detection, a clear face, not turned too far.
  final bool usable;
}

/// Reads a face on the phone: frame after frame through YuNet, alignment, EfficientNet-B0 and MediaPipe, keeping the
/// numbers of the usable frames only (never a picture), and pooling them into the 1,400-number vector the emotion model
/// reads. The same pipeline as the server's, checked against it.
class FaceReader {
  FaceReader({FaceModelRunner? runner}) : runner = runner ?? ChannelFaceModelRunner();

  final FaceModelRunner runner;
  final _tracker = FaceTracker();
  final _usable = <FaceFrame>[];

  static const _yunetSize = 640;

  /// How many usable frames have been kept for this recording.
  int get usableFrames => _usable.length;

  /// Loads the three models from [directory]. False when they cannot be opened.
  Future<bool> start(String directory) async {
    reset();
    return runner.load(directory);
  }

  /// Forgets everything about the recording so far.
  void reset() {
    _tracker.reset();
    _usable.clear();
  }

  /// The 1,400 numbers for everything read so far, or null when fewer than 3 frames were usable.
  Float32List? pooled() => poolFace(_usable);

  Future<void> close() => runner.close();

  /// One upright JPEG from the camera. Null when the frame could not be read at all.
  Future<FaceReading?> addJpeg(Uint8List jpeg) async {
    final clock = Stopwatch()..start();
    final reading = await _read(jpeg, clock);
    debugPrint('[FaceReader] frame ${reading == null ? 'skipped' : (reading.usable ? 'usable' : (reading.found ? 'found, not usable' : 'no face'))}: '
        '${clock.elapsedMilliseconds} ms in all; $_marks; kept so far: ${_usable.length}');
    return reading;
  }

  String _marks = '';

  Future<FaceReading?> _read(Uint8List jpeg, Stopwatch clock) async {
    final img = await runner.decode(jpeg);
    _marks = 'decode ${clock.elapsedMilliseconds}';
    if (img == null || img.w > _yunetSize || img.h > _yunetSize) return null; // the app's camera frames are 640 px at most

    // YuNet wants a 640x640 frame; the rest is padded with zeros (bottom and right), as OpenCV does.
    final padded = Uint8List(_yunetSize * _yunetSize * 3);
    for (var y = 0; y < img.h; y++) {
      padded.setRange(y * _yunetSize * 3, y * _yunetSize * 3 + img.w * 3, img.bgr, y * img.w * 3);
    }
    final out = await runner.yunet(padded);
    _marks += ', yunet ${clock.elapsedMilliseconds}';
    if (out == null) return null;
    final faces = decodeYuNet([
      for (final s in const [8, 16, 32]) YuNetStride(stride: s, cls: out['cls_$s']!, obj: out['obj_$s']!, bbox: out['bbox_$s']!, kps: out['kps_$s']!),
    ]);
    final pick = _tracker.update(faces, img.w, img.h);
    final face = pick.face;
    if (face == null) return const FaceReading(found: false, usable: false);

    final m = estimateSimilarity(face.points, faceTemplate);
    if (m == null) return FaceReading(found: pick.found || pick.tracked, usable: false);
    final b0 = await runner.b0(b0Input(warpToFace(img.bgr, img.w, img.h, m)));
    _marks += ', align+b0 ${clock.elapsedMilliseconds}';
    if (b0 == null || b0.length != 8 + 1280) return FaceReading(found: pick.found || pick.tracked, usable: false);

    // MediaPipe reads a square margin crop around the face.
    final crop = landmarkCrop(face, img.w, img.h);
    final cw = crop.x1 - crop.x0, ch = crop.y1 - crop.y0;
    var mediaPipeOk = false;
    var yaw = 0.0, pitch = 0.0;
    Float32List? blend;
    if (cw > 0 && ch > 0) {
      final rgb = Uint8List(cw * ch * 3);
      for (var y = 0; y < ch; y++) {
        var from = ((crop.y0 + y) * img.w + crop.x0) * 3;
        var to = y * cw * 3;
        for (var x = 0; x < cw; x++) {
          rgb[to] = img.bgr[from + 2];
          rgb[to + 1] = img.bgr[from + 1];
          rgb[to + 2] = img.bgr[from];
          from += 3;
          to += 3;
        }
      }
      final lm = await runner.landmarks(rgb, cw, ch);
      _marks += ', landmarks ${clock.elapsedMilliseconds} (cumulative ms)';
      if (lm != null && lm.length == 1 + 52 + 16 && lm[0] > 0) {
        mediaPipeOk = true;
        blend = Float32List.fromList(lm.sublist(1, 53));
        // MediaPipe's Java side hands the 4x4 matrix over column by column; the head pose maths reads it row by row.
        final cols = lm.sublist(53);
        final rows = [for (var i = 0; i < 4; i++) for (var j = 0; j < 4; j++) cols[j * 4 + i].toDouble()];
        final pose = headPose(rows);
        yaw = pose.yaw;
        pitch = pose.pitch;
      }
    }

    final usable = frameUsable(tracked: pick.tracked, mediaPipeOk: mediaPipeOk, faceHeight: face.h, yaw: yaw, pitch: pitch);
    if (usable) {
      _usable.add(FaceFrame(
        usable: true,
        logits: Float32List.fromList(b0.sublist(0, 8)),
        blendshapes: blend!,
        embedding: Float32List.fromList(b0.sublist(8)),
      ));
    }
    return FaceReading(found: true, usable: usable);
  }
}
