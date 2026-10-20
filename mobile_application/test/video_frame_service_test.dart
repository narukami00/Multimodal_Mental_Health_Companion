import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/video_frame_service.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSink implements WebSocketSink {
  _FakeSink(this.sent);

  final List<dynamic> sent;
  bool closed = false;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async => closed = true;

  @override
  Future<void> get done async {}
}

/// A socket whose server side the test plays by hand.
class _FakeChannel with StreamChannelMixin<dynamic> implements WebSocketChannel {
  final toApp = StreamController<dynamic>();
  final List<dynamic> sent = [];
  late final _FakeSink _sink = _FakeSink(sent);

  List<Map<String, dynamic>> get json => [
        for (final m in sent)
          if (m is String) jsonDecode(m) as Map<String, dynamic>,
      ];
  List<Uint8List> get binary => [
        for (final m in sent)
          if (m is Uint8List) m,
      ];

  void serverSays(Map<String, dynamic> message) => toApp.add(jsonEncode(message));

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get stream => toApp.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _FakeSource implements FrameSource {
  _FakeSource({this.opens = true});

  final bool opens;
  final controller = StreamController<Uint8List>.broadcast();
  bool started = false;
  int stops = 0;

  @override
  Stream<Uint8List> get frames => controller.stream;

  @override
  Future<bool> start() async => started = opens;

  @override
  Future<void> stop() async {
    started = false;
    stops++;
  }
}

Uint8List _jpeg(int marker) => Uint8List.fromList([0xff, 0xd8, marker, 0xff, 0xd9]);

void main() {
  late _FakeChannel channel;
  late _FakeSource source;
  late bool consent;
  late int connects;
  late VideoFrameService service;

  VideoFrameService build({
    Duration minGap = Duration.zero,
    Duration staleAfter = const Duration(seconds: 5),
    Duration handshake = const Duration(milliseconds: 300),
    Uri? uri,
    bool opens = true,
  }) {
    channel = _FakeChannel();
    source = _FakeSource(opens: opens);
    consent = true;
    connects = 0;
    return service = VideoFrameService(
      source: source,
      uriProvider: () => uri ?? Uri.parse('ws://127.0.0.1:8010/ws/v1/video?session_id=s1'),
      consentGranted: () => consent,
      connect: (_) {
        connects++;
        return channel;
      },
      minGap: minGap,
      staleAfter: staleAfter,
      handshakeTimeout: handshake,
    );
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

  tearDown(() async {
    await service.stop();
    unawaited(channel.toApp.close()); // never awaited: a controller nobody listened to only completes when someone does
    await source.controller.close();
  });

  test('without the camera consent nothing is opened at all', () async {
    build();
    consent = false;
    expect(await service.start(), isFalse);
    expect(connects, 0);
    expect(source.started, isFalse);
    expect(service.state, VideoStreamState.off);
  });

  test('with consent: handshake, then upright frames with a sequence number', () async {
    build();
    final starting = service.start();
    await settle();
    expect(channel.json.first, {'type': 'video.start', 'codec': 'jpeg', 'upright': true});
    channel.serverSays({'type': 'video.ready'});
    expect(await starting, isTrue);
    expect(service.streaming, isTrue);
    expect(source.started, isTrue);

    source.controller.add(_jpeg(1));
    await settle();
    final frame = channel.binary.single;
    expect(ByteData.sublistView(frame).getUint32(0, Endian.little), 0);
    expect(frame.sublist(4), _jpeg(1));

    channel.serverSays({'type': 'video.ack', 'seq': 0, 'usable': 1, 'dropped': 2});
    await settle();
    expect(service.lastUsable, isTrue);
    expect(service.serverDropped, 2);
    expect(service.framesSent, 1);
  });

  test('frames wait for the previous acknowledgement instead of piling up', () async {
    build();
    final starting = service.start();
    await settle();
    channel.serverSays({'type': 'video.ready'});
    await starting;

    for (var i = 0; i < 5; i++) {
      source.controller.add(_jpeg(i));
    }
    await settle();
    expect(channel.binary.length, 1); // the other four were dropped on the phone

    channel.serverSays({'type': 'video.ack', 'seq': 0, 'usable': 0, 'dropped': 0});
    await settle();
    expect(service.lastUsable, isFalse);
    source.controller.add(_jpeg(9));
    await settle();
    expect(channel.binary.length, 2);
  });

  test('withdrawing the consent stops the camera and the upload at the next frame', () async {
    build();
    final starting = service.start();
    await settle();
    channel.serverSays({'type': 'video.ready'});
    await starting;

    consent = false;
    source.controller.add(_jpeg(1));
    await settle();
    expect(channel.binary, isEmpty);
    expect(source.started, isFalse);
    expect(service.state, VideoStreamState.off);
    expect(channel.json.last, {'type': 'video.stop'});
  });

  test('a refusal by the server closes the camera and says why', () async {
    build();
    final starting = service.start();
    await settle();
    channel.serverSays({'type': 'video.refused', 'reason': 'no_consent'});
    expect(await starting, isFalse);
    expect(service.state, VideoStreamState.refused);
    expect(service.refusedReason, 'no_consent');
    expect(source.started, isFalse); // the camera was never even opened
  });

  test('a camera that will not open is an error, and the socket is closed', () async {
    build(opens: false);
    final starting = service.start();
    await settle();
    channel.serverSays({'type': 'video.ready'});
    expect(await starting, isFalse);
    expect(service.state, VideoStreamState.error);
    expect(channel.json.last, {'type': 'video.stop'});
  });

  test('a silent server times out and the camera stays closed', () async {
    build(handshake: const Duration(milliseconds: 80));
    expect(await service.start(), isFalse);
    expect(service.state, VideoStreamState.error);
    expect(source.started, isFalse);
  });

  test('no address (call not connected) is an error without any camera use', () async {
    build();
    final offline = VideoFrameService(
      source: source,
      uriProvider: () => null,
      consentGranted: () => true,
      connect: (_) => channel,
    );
    expect(await offline.start(), isFalse);
    expect(offline.state, VideoStreamState.error);
    expect(source.started, isFalse);
  });
}
