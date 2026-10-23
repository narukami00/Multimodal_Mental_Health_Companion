import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// An on-device model pack (the speech model, the camera models): where it lives, whether it is all there, how to
/// get it and how to remove it.
///
/// A pack is not part of the app. With the person's OK the app downloads it ONCE from their own companion server
/// (never a third party), straight to files so it never sits in memory, and checks every file is exactly the size
/// the server announced before the pack counts as installed. Nothing half-installed is ever left behind.
class ModelPackStore extends ChangeNotifier {
  ModelPackStore({
    required this.pack,
    required this.files,
    required this.folderName,
    Future<Directory> Function()? directory,
    Future<Uri?> Function()? serverBase,
  })  : _directory = directory ?? (() => _defaultDirectory(folderName)),
        _serverBase = serverBase;

  /// The name the server knows the pack by (`/v1/models/<pack>`).
  final String pack;

  /// The files the pack is made of.
  final List<String> files;

  /// The folder inside the app's private storage.
  final String folderName;

  final Future<Directory> Function() _directory;
  final Future<Uri?> Function()? _serverBase;

  static const _readyMarker = 'ready.json';

  static Future<Directory> _defaultDirectory(String folder) async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}models${Platform.pathSeparator}$folder');
  }

  /// The folder holding the pack when it is fully installed, else null.
  Future<String?> installedDirectory() async {
    try {
      final dir = await _directory();
      if (!await File('${dir.path}${Platform.pathSeparator}$_readyMarker').exists()) return null;
      for (final name in files) {
        if (!await File('${dir.path}${Platform.pathSeparator}$name').exists()) return null;
      }
      return dir.path;
    } catch (_) {
      return null; // no app folder to look in (for example in a test): not installed
    }
  }

  Future<bool> isInstalled() async => await installedDirectory() != null;

  /// Bytes the installed pack takes on the phone, or null when it is not installed.
  Future<int?> installedBytes() async {
    final path = await installedDirectory();
    if (path == null) return null;
    var total = 0;
    for (final name in files) {
      total += await File('$path${Platform.pathSeparator}$name').length();
    }
    return total;
  }

  /// Downloads the pack from the companion server. [onProgress] gets 0..1. Returns true when it is installed;
  /// false (and nothing half-installed is left behind) when the server is away, does not have the pack, or a file
  /// is wrong.
  Future<bool> download({void Function(double progress)? onProgress}) async {
    final base = await _serverBase?.call();
    if (base == null) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final dir = await _directory();
      final manifestReply = await (await client.getUrl(base.replace(path: '/v1/models/$pack'))).close();
      if (manifestReply.statusCode != 200) {
        await manifestReply.drain<void>();
        return false;
      }
      final manifest = jsonDecode(await manifestReply.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final listed = [
        for (final f in (manifest['files'] as List).whereType<Map>()) (name: f['name'] as String, size: (f['size'] as num).toInt()),
      ];
      if (!files.every((n) => listed.any((f) => f.name == n))) return false;

      await remove();
      await dir.create(recursive: true);
      final wanted = listed.where((f) => files.contains(f.name)).toList();
      final total = wanted.fold<int>(0, (n, f) => n + f.size);
      var done = 0;
      for (final f in wanted) {
        final part = File('${dir.path}${Platform.pathSeparator}${f.name}.part');
        final reply = await (await client.getUrl(base.replace(path: '/v1/models/$pack/${f.name}'))).close();
        if (reply.statusCode != 200) {
          await reply.drain<void>();
          throw const HttpException('model file refused');
        }
        final sink = part.openWrite();
        try {
          await for (final chunk in reply) {
            sink.add(chunk);
            done += chunk.length;
            onProgress?.call(total == 0 ? 0 : done / total);
          }
        } finally {
          await sink.close();
        }
        if (await part.length() != f.size) throw const HttpException('model file has the wrong size');
        await part.rename('${dir.path}${Platform.pathSeparator}${f.name}');
      }
      await File('${dir.path}${Platform.pathSeparator}$_readyMarker').writeAsString(jsonEncode(manifest));
      onProgress?.call(1);
      final ok = await isInstalled();
      notifyListeners();
      return ok;
    } catch (e) {
      debugPrint('[ModelPack:$pack] download failed: ${e.runtimeType}');
      await remove();
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Deletes the pack (and any half-finished download) from the phone.
  Future<void> remove() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    notifyListeners();
  }
}
