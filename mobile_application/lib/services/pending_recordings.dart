import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Voice and video recordings that are waiting for the companion server to write them down.
///
/// Each one is a raw 16 kHz mono PCM file in the app's PRIVATE storage (no other app can read it, and it is
/// not part of the gallery or the backups folder). It is deleted the moment the server has read it, or when
/// the entry is deleted. Nothing else about a recording is ever kept: no pictures, no video.
class PendingRecordings {
  PendingRecordings({Future<Directory> Function()? directory}) : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}pending_recordings');
  }

  Future<File> _file(String id) async {
    final dir = await _directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    // ids are numbers made by the app; strip anything else so an id can never name a path
    final safe = id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '');
    return File('${dir.path}${Platform.pathSeparator}$safe.pcm');
  }

  /// True when the recording was written. False (never an exception) when the phone refuses, e.g. it is full.
  Future<bool> save(String id, Uint8List pcm) async {
    try {
      await (await _file(id)).writeAsBytes(pcm, flush: true);
      return true;
    } catch (e) {
      debugPrint('[Pending] could not keep a recording: ${e.runtimeType}');
      return false;
    }
  }

  Future<Uint8List?> read(String id) async {
    try {
      final file = await _file(id);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<File> _faceFile(String id) async {
    final audio = await _file(id);
    return File('${audio.path.substring(0, audio.path.length - 4)}.face');
  }

  /// The face numbers the phone read for this recording (1,400 float32 values: 5,600 bytes, never a picture), kept
  /// beside the audio until the server has read them. False when the phone refuses.
  Future<bool> saveFace(String id, Float32List vector) async {
    try {
      await (await _faceFile(id)).writeAsBytes(vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes), flush: true);
      return true;
    } catch (e) {
      debugPrint('[Pending] could not keep the face numbers: ${e.runtimeType}');
      return false;
    }
  }

  Future<Float32List?> readFace(String id) async {
    try {
      final file = await _faceFile(id);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length != 1400 * 4) return null;
      return Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes, 1400));
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    try {
      final file = await _file(id);
      if (await file.exists()) await file.delete();
      final face = await _faceFile(id);
      if (await face.exists()) await face.delete();
    } catch (_) {}
  }
}
