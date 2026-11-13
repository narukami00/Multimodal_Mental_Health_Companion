import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'secure_storage.dart';

/// Voice and video recordings that are waiting for the companion server to write them down.
///
/// Each one is a raw 16 kHz mono PCM file (and optional 1400-float face vector) in the app's PRIVATE storage,
/// encrypted at rest with [SecureCipher] when available. It is deleted the moment the server has read it,
/// when the entry is deleted, or when its retention window expires.
class PendingRecordings {
  PendingRecordings({
    Future<Directory> Function()? directory,
    SecureCipher? cipher,
  })  : _directory = directory ?? _defaultDirectory,
        _encrypted = cipher == null ? null : EncryptedFileStore(cipher: cipher);

  final Future<Directory> Function() _directory;
  final EncryptedFileStore? _encrypted;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}pending_recordings');
  }

  String _safeId(String id) => id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '');

  Future<File> _file(String id) async {
    final dir = await _directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}${_safeId(id)}.pcm');
  }

  Future<File> _encryptedFile(String id) async {
    final dir = await _directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}${_safeId(id)}.pcm.enc');
  }

  Future<File> _faceFile(String id) async {
    final dir = await _directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}${_safeId(id)}.face');
  }

  Future<File> _encryptedFaceFile(String id) async {
    final dir = await _directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}${_safeId(id)}.face.enc');
  }

  Uint8List _aad(String id, String kind) => Uint8List.fromList(utf8.encode('pending:${_safeId(id)}:$kind'));

  /// True when the recording was written. False (never an exception) when the phone refuses, e.g. it is full.
  Future<bool> save(String id, Uint8List pcm) async {
    try {
      final enc = _encrypted;
      if (enc != null) {
        final target = await _encryptedFile(id);
        await enc.writeAtomic(target, pcm, aad: _aad(id, 'pcm'));
        final legacy = await _file(id);
        if (await legacy.exists()) await legacy.delete();
        return true;
      }
      final file = await _file(id);
      await file.writeAsBytes(pcm, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Null when the recording is gone or unreadable. Propagates [SecureStorageException] on tamper.
  Future<Uint8List?> read(String id) async {
    final enc = _encrypted;
    if (enc != null) {
      final encFile = await _encryptedFile(id);
      await enc.cleanupStaleTemp(encFile);
      final decrypted = await enc.readDecrypted(encFile, aad: _aad(id, 'pcm'));
      if (decrypted != null) {
        final legacy = await _file(id);
        if (await legacy.exists()) await legacy.delete();
        return decrypted;
      }
      // Migrate legacy plaintext .pcm if present.
      try {
        final legacy = await _file(id);
        if (!await legacy.exists()) return null;
        final raw = await legacy.readAsBytes();
        await enc.writeAtomic(encFile, raw, aad: _aad(id, 'pcm'));
        await legacy.delete();
        return raw;
      } catch (e) {
        if (e is SecureStorageException) rethrow;
        return null;
      }
    }
    try {
      final file = await _file(id);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// The 1400-float face summary for a video journal made while the server was away (5600 bytes).
  /// Kept only until the entry is analyzed or deleted; deleted alongside the audio.
  Future<bool> saveFace(String id, Float32List vector) async {
    try {
      final bytes = vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes);
      final enc = _encrypted;
      if (enc != null) {
        final target = await _encryptedFaceFile(id);
        await enc.writeAtomic(target, bytes, aad: _aad(id, 'face'));
        final legacy = await _faceFile(id);
        if (await legacy.exists()) await legacy.delete();
        return true;
      }
      final file = await _faceFile(id);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Float32List?> readFace(String id) async {
    final enc = _encrypted;
    if (enc != null) {
      final encFile = await _encryptedFaceFile(id);
      await enc.cleanupStaleTemp(encFile);
      final decrypted = await enc.readDecrypted(encFile, aad: _aad(id, 'face'));
      if (decrypted != null) {
        final legacy = await _faceFile(id);
        if (await legacy.exists()) await legacy.delete();
        return _bytesToFaceVector(decrypted);
      }
      try {
        final legacy = await _faceFile(id);
        if (!await legacy.exists()) return null;
        final raw = await legacy.readAsBytes();
        await enc.writeAtomic(encFile, raw, aad: _aad(id, 'face'));
        await legacy.delete();
        return _bytesToFaceVector(raw);
      } catch (e) {
        if (e is SecureStorageException) rethrow;
        return null;
      }
    }
    try {
      final file = await _faceFile(id);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return _bytesToFaceVector(bytes);
    } catch (_) {
      return null;
    }
  }

  Float32List? _bytesToFaceVector(Uint8List bytes) {
    if (bytes.length % Float32List.bytesPerElement != 0) return null;
    return Uint8List.fromList(bytes).buffer.asFloat32List();
  }

  /// Deletes only the pending face vector for [id] (e.g., if face consent was revoked).
  Future<bool> deleteFace(String id) async {
    var ok = true;
    for (final file in <File>[
      await _faceFile(id),
      await _encryptedFaceFile(id),
      File('${(await _encryptedFaceFile(id)).path}.tmp'),
    ]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[PendingRecordings] Failed to delete face artifact ${file.path}: $e');
        ok = false;
      }
    }
    return ok;
  }

  /// Deletes all pending audio and face artifacts for [id]. Returns `false` if any file failed to delete.
  Future<bool> delete(String id) async {
    var ok = true;
    for (final file in <File>[
      await _file(id),
      await _encryptedFile(id),
      File('${(await _encryptedFile(id)).path}.tmp'),
      await _faceFile(id),
      await _encryptedFaceFile(id),
      File('${(await _encryptedFaceFile(id)).path}.tmp'),
    ]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[PendingRecordings] Failed to delete ${file.path}: $e');
        ok = false;
      }
    }
    return ok;
  }

  /// Deletes pending recording files whose session ID is not in [activeSessionIds].
  Future<int> reconcileOrphans(Set<String> activeSessionIds) async {
    final safeActive = activeSessionIds.map(_safeId).toSet();
    final dir = await _directory();
    if (!await dir.exists()) return 0;
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final id = _extractIdFromFilename(name);
      if (id == null || !safeActive.contains(id)) {
        try {
          await entity.delete();
          removed++;
        } catch (e) {
          debugPrint('[PendingRecordings] Failed to remove orphan $name: $e');
        }
      }
    }
    return removed;
  }

  /// Deletes pending recording files older than [maxAge].
  Future<int> pruneExpired(Duration maxAge, {DateTime? now}) async {
    final dir = await _directory();
    if (!await dir.exists()) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final modified = await entity.lastModified();
        if (modified.isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      } catch (e) {
        debugPrint('[PendingRecordings] Failed to prune expired file ${entity.path}: $e');
      }
    }
    return removed;
  }

  static String? _extractIdFromFilename(String name) {
    for (final suffix in const ['.pcm.enc.tmp', '.face.enc.tmp', '.pcm.enc', '.face.enc', '.pcm', '.face']) {
      if (name.endsWith(suffix)) {
        return name.substring(0, name.length - suffix.length);
      }
    }
    return null;
  }
}
