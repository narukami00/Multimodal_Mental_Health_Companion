import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when encrypted storage fails to encrypt, decrypt, or verify integrity.
class SecureStorageException implements Exception {
  SecureStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null ? 'SecureStorageException: $message' : 'SecureStorageException: $message ($cause)';
}

/// Authenticated encryption primitive for sensitive local data.
abstract class SecureCipher {
  Future<bool> isAvailable();
  Future<Uint8List> encrypt(Uint8List plaintext, {Uint8List? aad});
  Future<Uint8List> decrypt(Uint8List ciphertext, {Uint8List? aad});
}

/// Android Keystore-backed AES-256-GCM cipher over a MethodChannel.
class AndroidKeystoreCipher implements SecureCipher {
  AndroidKeystoreCipher({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.sysmentalhealth.solace_mobile/secure_crypto';
  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> encrypt(Uint8List plaintext, {Uint8List? aad}) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('encrypt', <String, Object?>{
        'plaintext': plaintext,
        if (aad != null && aad.isNotEmpty) 'aad': aad,
      });
      if (result == null) {
        throw SecureStorageException('Platform cipher returned null ciphertext');
      }
      return result;
    } on PlatformException catch (e) {
      throw SecureStorageException('Android Keystore encryption failed: ${e.message ?? e.code}', e);
    } on MissingPluginException catch (e) {
      throw SecureStorageException('Android Keystore channel unavailable', e);
    }
  }

  @override
  Future<Uint8List> decrypt(Uint8List ciphertext, {Uint8List? aad}) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('decrypt', <String, Object?>{
        'ciphertext': ciphertext,
        if (aad != null && aad.isNotEmpty) 'aad': aad,
      });
      if (result == null) {
        throw SecureStorageException('Platform cipher returned null plaintext');
      }
      return result;
    } on PlatformException catch (e) {
      throw SecureStorageException('Android Keystore decryption failed: ${e.message ?? e.code}', e);
    } on MissingPluginException catch (e) {
      throw SecureStorageException('Android Keystore channel unavailable', e);
    }
  }
}

/// Atomic encrypted file operations with read-back verification and tamper propagation.
class EncryptedFileStore {
  EncryptedFileStore({SecureCipher? cipher}) : _cipher = cipher ?? AndroidKeystoreCipher();

  final SecureCipher _cipher;

  Future<bool> isCipherAvailable() => _cipher.isAvailable();

  /// Encrypts [plaintext], writes to a `.tmp` sibling, verifies read-back decryption,
  /// and atomically renames to [target].
  Future<void> writeAtomic(File target, Uint8List plaintext, {Uint8List? aad}) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    final encrypted = await _cipher.encrypt(plaintext, aad: aad);
    await tmp.writeAsBytes(encrypted, flush: true);

    final verifyBytes = await tmp.readAsBytes();
    final decrypted = await _cipher.decrypt(verifyBytes, aad: aad);
    if (!_bytesEqual(decrypted, plaintext)) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      throw SecureStorageException('Read-back verification failed for ${target.path}');
    }

    if (await target.exists()) {
      await target.delete();
    }
    await tmp.rename(target.path);
  }

  /// Reads and decrypts [target]. Returns `null` only if [target] does not exist.
  /// Throws [SecureStorageException] if [target] is tampered or corrupt.
  Future<Uint8List?> readDecrypted(File target, {Uint8List? aad}) async {
    if (!await target.exists()) return null;
    final bytes = await target.readAsBytes();
    return _cipher.decrypt(bytes, aad: aad);
  }

  /// Cleans up a leftover `.tmp` file from an interrupted write.
  Future<void> cleanupStaleTemp(File target) async {
    final tmp = File('${target.path}.tmp');
    if (await tmp.exists()) {
      await tmp.delete();
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Encrypted key-value store for sensitive JSON payloads, with atomic migration
/// from legacy [SharedPreferences] entries.
class SecureKeyValueStore {
  SecureKeyValueStore({
    required Future<Directory> Function() directoryProvider,
    SecureCipher? cipher,
  })  : _directoryProvider = directoryProvider,
        _files = EncryptedFileStore(cipher: cipher);

  /// Default app-documents backed store under `secure_stores/`.
  static Future<SecureKeyValueStore> createDefault({SecureCipher? cipher}) async {
    final store = SecureKeyValueStore(
      directoryProvider: () async {
        final docs = await getApplicationDocumentsDirectory();
        return Directory('${docs.path}${Platform.pathSeparator}secure_stores');
      },
      cipher: cipher,
    );
    return store;
  }

  final Future<Directory> Function() _directoryProvider;
  final EncryptedFileStore _files;

  Future<bool> isAvailable() => _files.isCipherAvailable();

  Future<File> _fileForKey(String key) async {
    final dir = await _directoryProvider();
    final safe = key.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.enc');
  }

  Uint8List _aadForKey(String key) => Uint8List.fromList(utf8.encode('kv:$key'));

  /// Reads [key] from encrypted storage. If not yet migrated and [legacyPreferences]
  /// holds a plaintext entry for [key], atomically migrates it to encrypted storage,
  /// verifies read-back, and only then removes the legacy plaintext key.
  Future<String?> readString(String key, {SharedPreferences? legacyPreferences}) async {
    final file = await _fileForKey(key);
    await _files.cleanupStaleTemp(file);
    final aad = _aadForKey(key);
    final existing = await _files.readDecrypted(file, aad: aad);
    if (existing != null) {
      if (legacyPreferences != null && legacyPreferences.containsKey(key)) {
        await legacyPreferences.remove(key);
      }
      return utf8.decode(existing);
    }
    if (legacyPreferences == null) return null;
    final legacy = legacyPreferences.getString(key);
    if (legacy == null) return null;
    await writeString(key, legacy);
    await legacyPreferences.remove(key);
    return legacy;
  }

  /// Writes [value] for [key] atomically with authenticated encryption.
  Future<void> writeString(String key, String value) async {
    final file = await _fileForKey(key);
    final bytes = Uint8List.fromList(utf8.encode(value));
    await _files.writeAtomic(file, bytes, aad: _aadForKey(key));
  }

  /// Reads a `List<String>` for [key], migrating from [legacyPreferences] if needed.
  Future<List<String>> readStringList(String key, {SharedPreferences? legacyPreferences}) async {
    final file = await _fileForKey(key);
    await _files.cleanupStaleTemp(file);
    final aad = _aadForKey(key);
    final existing = await _files.readDecrypted(file, aad: aad);
    if (existing != null) {
      if (legacyPreferences != null && legacyPreferences.containsKey(key)) {
        await legacyPreferences.remove(key);
      }
      final decoded = jsonDecode(utf8.decode(existing));
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
      return const [];
    }
    if (legacyPreferences == null) return const [];
    final legacy = legacyPreferences.getStringList(key);
    if (legacy == null) return const [];
    await writeStringList(key, legacy);
    await legacyPreferences.remove(key);
    return legacy;
  }

  /// Writes a `List<String>` for [key] atomically with authenticated encryption.
  Future<void> writeStringList(String key, List<String> values) async {
    await writeString(key, jsonEncode(values));
  }

  /// Deletes the encrypted entry for [key] (and any legacy entry if provided).
  Future<void> remove(String key, {SharedPreferences? legacyPreferences}) async {
    final file = await _fileForKey(key);
    await _files.cleanupStaleTemp(file);
    if (await file.exists()) {
      await file.delete();
    }
    if (legacyPreferences != null && legacyPreferences.containsKey(key)) {
      await legacyPreferences.remove(key);
    }
  }
}
