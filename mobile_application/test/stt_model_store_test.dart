import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/model_pack_store.dart';
import 'package:solace_mobile/services/phone_transcriber.dart';
import 'package:solace_mobile/services/stt_model_store.dart';

/// A tiny stand-in for the companion server's model routes.
class _ModelServer {
  late HttpServer server;
  final files = <String, List<int>>{
    WhisperModelFiles.encoderName: List.filled(1000, 1),
    WhisperModelFiles.decoderName: List.filled(3000, 2),
    WhisperModelFiles.tokensName: List.filled(200, 3),
  };
  bool hasModel = true;
  int shortBy = 0; // serve this many bytes fewer than announced, to mimic a cut-off download

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (!hasModel) {
        request.response.statusCode = 404;
      } else if (path == '/v1/models/stt') {
        request.response.write(jsonEncode({
          'model': 'whisper-base.en',
          'files': [for (final e in files.entries) {'name': e.key, 'size': e.value.length}],
        }));
      } else {
        final bytes = files[path.split('/').last];
        if (bytes == null) {
          request.response.statusCode = 404;
        } else {
          request.response.add(bytes.sublist(0, bytes.length - shortBy));
        }
      }
      await request.response.close();
    });
  }

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');
}

void main() {
  late Directory dir;
  late _ModelServer server;
  late SttModelStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('stt_store_');
    server = _ModelServer();
    await server.start();
    store = SttModelStore(directory: () async => Directory('${dir.path}/model'), serverBase: () async => server.base);
  });

  tearDown(() async {
    await server.server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  test('is not installed until it has been downloaded', () async {
    expect(await store.installed(), isNull);
  });

  test('downloads all three files, reports progress up to 100%, and is then installed', () async {
    final seen = <double>[];
    expect(await store.download(onProgress: seen.add), isTrue);
    final files = await store.installed();
    expect(files, isNotNull);
    expect(File(files!.encoder).lengthSync(), 1000);
    expect(File(files.decoder).lengthSync(), 3000);
    expect(File(files.tokens).lengthSync(), 200);
    expect(seen.last, 1.0);
    expect(seen.every((p) => p >= 0 && p <= 1), isTrue);
    expect(Directory('${dir.path}/model').listSync().where((e) => e.path.endsWith('.part')), isEmpty);
  });

  test('a server with no model leaves nothing behind', () async {
    server.hasModel = false;
    expect(await store.download(), isFalse);
    expect(await store.installed(), isNull);
  });

  test('a cut-off file is refused and nothing half-installed is kept', () async {
    server.shortBy = 1;
    expect(await store.download(), isFalse);
    expect(await store.installed(), isNull);
    expect(Directory('${dir.path}/model').existsSync(), isFalse);
  });

  group('why a download did not finish', () {
    test('a good download says installed, and the plain download() still answers true', () async {
      expect(await store.downloadResult(), ModelDownload.installed);
      expect(await store.download(), isTrue);
    });

    test('no server at all is "server away"', () async {
      final away = SttModelStore(directory: () async => Directory('${dir.path}/model'), serverBase: () async => null);
      expect(await away.downloadResult(), ModelDownload.serverAway);
      final unreachable = SttModelStore(directory: () async => Directory('${dir.path}/model'), serverBase: () async => Uri.parse('http://127.0.0.1:1'));
      expect(await unreachable.downloadResult(), ModelDownload.serverAway); // nothing listens: could not connect
    });

    test('a server without the model is "not on the server"', () async {
      server.hasModel = false;
      expect(await store.downloadResult(), ModelDownload.notOnServer);
      expect(await store.installed(), isNull);
    });

    test('a file that arrives short is "interrupted" and nothing is kept', () async {
      server.shortBy = 1;
      expect(await store.downloadResult(), ModelDownload.interrupted);
      expect(Directory('${dir.path}/model').existsSync(), isFalse);
    });

    test('a full phone is "no space", not a mystery', () async {
      final full = SttModelStore(
        directory: () async => throw FileSystemException('write failed', '/data', const OSError('No space left on device', 28)),
        serverBase: () async => server.base,
      );
      expect(await full.downloadResult(), ModelDownload.noSpace);
    });

    test('the pack knows roughly how big it is, to say so', () {
      expect(SttModelStore().sizeMegabytes, 153);
      expect(FaceModelStore().sizeMegabytes, 19);
    });
  });

  test('no server means no download, and removing deletes the model', () async {
    final away = SttModelStore(directory: () async => Directory('${dir.path}/model'), serverBase: () async => null);
    expect(await away.download(), isFalse);

    expect(await store.download(), isTrue);
    await store.remove();
    expect(await store.installed(), isNull);
  });
}
