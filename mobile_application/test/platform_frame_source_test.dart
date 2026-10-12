import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/platform_frame_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const control = MethodChannel('test/camera_control');
  final calls = <String>[];

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(control, null);
  });

  void answer(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call.method);
      return handler(call);
    });
  }

  test('start asks the native side to open the camera and reports its answer', () async {
    answer((_) => true);
    final source = PlatformFrameSource(control: control, stream: const EventChannel('test/camera_stream'));
    expect(await source.start(), isTrue);
    expect(calls, ['start']);
  });

  test('a denied permission or a camera that will not open is just false', () async {
    answer((_) => false);
    final source = PlatformFrameSource(control: control, stream: const EventChannel('test/camera_stream'));
    expect(await source.start(), isFalse);
    expect(await source.hasPermission(), isFalse);
  });

  test('a native error never throws into the app', () async {
    answer((_) => throw PlatformException(code: 'camera_in_use'));
    final source = PlatformFrameSource(control: control, stream: const EventChannel('test/camera_stream'));
    expect(await source.start(), isFalse);
    await source.stop(); // must not throw either
  });

  test('without any native side (tests, other platforms) it quietly says no', () async {
    final source = PlatformFrameSource(control: const MethodChannel('nothing/here'), stream: const EventChannel('nothing/there'));
    expect(await source.start(), isFalse);
    expect(await source.hasPermission(), isFalse);
    await source.stop();
  });

  test('only binary frames come through the stream', () async {
    const stream = EventChannel('test/camera_stream_frames');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      stream,
      MockStreamHandler.inline(onListen: (arguments, events) {
        events.success(Uint8List.fromList([1, 2, 3]));
        events.success('not a frame');
        events.endOfStream();
      }),
    );
    final source = PlatformFrameSource(control: control, stream: stream);
    expect(await source.frames.toList(), [
      Uint8List.fromList([1, 2, 3]),
    ]);
  });
}
