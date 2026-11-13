import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/services/secure_storage.dart';

import 'support/in_memory_test_cipher.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('solace_secure_storage_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('EncryptedFileStore round-trip, AAD binding, and tamper detection', () async {
    final store = EncryptedFileStore(cipher: InMemoryTestCipher());
    final target = File('${tempDir.path}/payload.enc');
    final aad = Uint8List.fromList('item-1'.codeUnits);
    final payload = Uint8List.fromList('sensitive journal transcript'.codeUnits);

    await store.writeAtomic(target, payload, aad: aad);
    expect(await target.exists(), isTrue);
    expect(await File('${target.path}.tmp').exists(), isFalse);

    final decrypted = await store.readDecrypted(target, aad: aad);
    expect(decrypted, payload);

    // Wrong AAD must throw rather than return corrupt plaintext.
    await expectLater(
      store.readDecrypted(target, aad: Uint8List.fromList('item-2'.codeUnits)),
      throwsA(isA<SecureStorageException>()),
    );

    // Tampering a single byte must throw SecureStorageException.
    final raw = await target.readAsBytes();
    raw[raw.length - 1] ^= 0xFF;
    await target.writeAsBytes(raw, flush: true);
    await expectLater(
      store.readDecrypted(target, aad: aad),
      throwsA(isA<SecureStorageException>()),
    );
  });

  test('SecureKeyValueStore migrates legacy SharedPreferences atomically and cleans up .tmp', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'solace.sessions.v1': '[{"id":"s1","transcript":"private"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final kv = SecureKeyValueStore(
      directoryProvider: () async => tempDir,
      cipher: InMemoryTestCipher(),
    );

    // Simulate a leftover .tmp file from a prior crash.
    final staleTmp = File('${tempDir.path}/solace.sessions.v1.enc.tmp');
    await staleTmp.writeAsString('partial-crash-bytes', flush: true);

    final read = await kv.readString('solace.sessions.v1', legacyPreferences: prefs);
    expect(read, '[{"id":"s1","transcript":"private"}]');

    // Legacy plaintext key removed only after verified encrypted write.
    expect(prefs.containsKey('solace.sessions.v1'), isFalse);
    expect(await staleTmp.exists(), isFalse);
    final encryptedFile = File('${tempDir.path}/solace.sessions.v1.enc');
    expect(await encryptedFile.exists(), isTrue);
    final rawOnDisk = String.fromCharCodes(await encryptedFile.readAsBytes());
    expect(rawOnDisk.contains('private'), isFalse);

    // Subsequent read without legacyPreferences still decrypts cleanly.
    final secondRead = await kv.readString('solace.sessions.v1');
    expect(secondRead, '[{"id":"s1","transcript":"private"}]');
  });
}
