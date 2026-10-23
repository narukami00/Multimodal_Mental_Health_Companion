import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/face_math.dart';
import 'package:solace_mobile/services/face_reader.dart';

/// YuNet outputs with exactly one strong face (stride 32, row 7, column 10): a 128 x 160 box centred at (336, 240) whose
/// five points are the alignment template shifted onto it.
Map<String, Float32List> _yunetWithOneFace() {
  final out = <String, Float32List>{};
  for (final s in [8, 16, 32]) {
    final n = (640 ~/ s) * (640 ~/ s);
    out['cls_$s'] = Float32List(n);
    out['obj_$s'] = Float32List(n);
    out['bbox_$s'] = Float32List(n * 4);
    out['kps_$s'] = Float32List(n * 10);
  }
  const row = 7, col = 10, idx = row * 20 + col;
  out['cls_32']![idx] = 0.9;
  out['obj_32']![idx] = 0.9;
  out['bbox_32']!.setAll(idx * 4, [0.5, 0.5, math.log(4), math.log(5)]);
  for (var j = 0; j < 10; j++) {
    final absolute = faceTemplate[j] + (j.isEven ? 224 : 101);
    out['kps_32']![idx * 10 + j] = absolute / 32 - (j.isEven ? col : row);
  }
  return out;
}

Map<String, Float32List> _yunetWithNoFace() => {
      for (final s in [8, 16, 32]) ...{
        'cls_$s': Float32List((640 ~/ s) * (640 ~/ s)),
        'obj_$s': Float32List((640 ~/ s) * (640 ~/ s)),
        'bbox_$s': Float32List((640 ~/ s) * (640 ~/ s) * 4),
        'kps_$s': Float32List((640 ~/ s) * (640 ~/ s) * 10),
      },
    };

class _FakeRunner implements FaceModelRunner {
  _FakeRunner();

  bool face = true;
  bool landmarkFace = true;
  int width = 640, height = 480;
  Float32List? lastB0Input;
  ({int w, int h})? lastLandmarkCrop;
  int decodes = 0, loads = 0;
  bool loadWorks = true;

  @override
  Future<bool> load(String directory) async {
    loads++;
    return loadWorks;
  }

  @override
  Future<bool> isLoaded() async => loadWorks;

  @override
  Future<void> close() async {}

  @override
  Future<({int w, int h, Uint8List bgr})?> decode(Uint8List jpeg) async {
    decodes++;
    return (w: width, h: height, bgr: Uint8List(width * height * 3));
  }

  @override
  Future<Map<String, Float32List>?> yunet(Uint8List paddedBgr) async {
    expect(paddedBgr.length, 640 * 640 * 3);
    return face ? _yunetWithOneFace() : _yunetWithNoFace();
  }

  @override
  Future<Float32List?> b0(Float32List input) async {
    lastB0Input = input;
    return Float32List.fromList([for (var i = 1; i <= 8; i++) i.toDouble(), for (var i = 0; i < 1280; i++) 0.5]);
  }

  @override
  Future<Float32List?> landmarks(Uint8List rgb, int w, int h) async {
    lastLandmarkCrop = (w: w, h: h);
    expect(rgb.length, w * h * 3);
    if (!landmarkFace) return null;
    final identity = [for (var i = 0; i < 4; i++) for (var j = 0; j < 4; j++) i == j ? 1.0 : 0.0];
    return Float32List.fromList([1, for (var i = 0; i < 52; i++) 0.25, ...identity]);
  }
}

void main() {
  final jpeg = Uint8List.fromList([1, 2, 3]);

  test('a clear frame goes through all three networks with the right inputs, and counts', () async {
    final runner = _FakeRunner();
    final reader = FaceReader(runner: runner);
    expect(await reader.start('/models'), isTrue);

    final r = await reader.addJpeg(jpeg);
    expect(r!.found, isTrue);
    expect(r.usable, isTrue);
    expect(reader.usableFrames, 1);
    expect(runner.lastB0Input!.length, 3 * faceInput * faceInput);
    // the margin crop around a 128 x 160 face centred at (336, 240): a 240 px square
    expect(runner.lastLandmarkCrop!.w, inInclusiveRange(240, 241));
    expect(runner.lastLandmarkCrop!.h, inInclusiveRange(240, 241));
  });

  test('three clear frames pool into the 1,400-number vector; two do not', () async {
    final reader = FaceReader(runner: _FakeRunner());
    await reader.start('/models');
    await reader.addJpeg(jpeg);
    await reader.addJpeg(jpeg);
    expect(reader.pooled(), isNull);
    await reader.addJpeg(jpeg);
    final v = reader.pooled()!;
    expect(v.length, faceVectorLength);
    expect(v.sublist(0, 8), [1, 2, 3, 4, 5, 6, 7, 8]); // mean of the B0 scores
    expect(v.sublist(8, 16), everyElement(0)); // identical frames: no spread
    expect(v[16], closeTo(0.25, 1e-6)); // mean expression value
    expect(v[120], closeTo(0.5, 1e-6)); // mean embedding
  });

  test('a frame where MediaPipe finds no face is found but not usable, and is not counted', () async {
    final runner = _FakeRunner()..landmarkFace = false;
    final reader = FaceReader(runner: runner);
    await reader.start('/models');
    final r = await reader.addJpeg(jpeg);
    expect(r!.found, isTrue);
    expect(r.usable, isFalse);
    expect(reader.usableFrames, 0);
  });

  test('a face that vanishes is carried over for two frames (found, but not usable), then lost', () async {
    final runner = _FakeRunner();
    final reader = FaceReader(runner: runner);
    await reader.start('/models');
    await reader.addJpeg(jpeg);
    runner.face = false;
    final a = await reader.addJpeg(jpeg);
    expect(a!.found, isTrue);
    expect(a.usable, isFalse);
    expect((await reader.addJpeg(jpeg))!.found, isTrue);
    final c = await reader.addJpeg(jpeg);
    expect(c!.found, isFalse);
    expect(reader.usableFrames, 1);
  });

  test('a frame bigger than 640 px is declined rather than read badly, and reset forgets everything', () async {
    final runner = _FakeRunner();
    final reader = FaceReader(runner: runner);
    await reader.start('/models');
    await reader.addJpeg(jpeg);
    runner.width = 1280;
    runner.height = 720;
    expect(await reader.addJpeg(jpeg), isNull);
    reader.reset();
    expect(reader.usableFrames, 0);
    expect(reader.pooled(), isNull);
  });

  test('says so when the models cannot be loaded', () async {
    final reader = FaceReader(runner: _FakeRunner()..loadWorks = false);
    expect(await reader.start('/models'), isFalse);
  });
}
