import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// How a model download ended.
enum ModelDownload {
  installed,

  /// The companion server could not be reached (or is in trouble).
  serverAway,

  /// The server is there, but does not have this model set up.
  notOnServer,

  /// The download broke off or arrived wrong; nothing was kept.
  interrupted,

  /// The phone has no room for it.
  noSpace,
}

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
    this.sizeMegabytes,
    Future<Directory> Function()? directory,
    Future<Uri?> Function()? serverBase,
  })  : _directory = directory ?? (() => _defaultDirectory(folderName)),
        _serverBase = serverBase;

  /// About how much room the pack takes, for telling the person (null when not known).
  final int? sizeMegabytes;

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

  /// Downloads the pack from the companion server. [onProgress] gets 0..1. Returns true when it is installed; false
  /// (and nothing half-installed is left behind) otherwise. [downloadResult] says why.
  Future<bool> download({void Function(double progress)? onProgress}) async =>
      await downloadResult(onProgress: onProgress) == ModelDownload.installed;

  /// Like [download], but says how it ended, so the person can be told what is actually wrong.
  Future<ModelDownload> downloadResult({void Function(double progress)? onProgress}) async {
    final base = await _serverBase?.call();
    if (base == null) return ModelDownload.serverAway;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    var gotManifest = false; // before it, a failure means the server could not be reached; after it, the download broke off
    try {
      final dir = await _directory();
      final manifestReply = await (await client.getUrl(base.replace(path: '/v1/models/$pack'))).close();
      if (manifestReply.statusCode != 200) {
        await manifestReply.drain<void>();
        return manifestReply.statusCode == 404 ? ModelDownload.notOnServer : ModelDownload.serverAway;
      }
      final manifest = jsonDecode(await manifestReply.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final listed = [
        for (final f in (manifest['files'] as List).whereType<Map>()) (name: f['name'] as String, size: (f['size'] as num).toInt()),
      ];
      if (!files.every((n) => listed.any((f) => f.name == n))) return ModelDownload.notOnServer;
      gotManifest = true;

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
          await remove();
          return reply.statusCode == 404 ? ModelDownload.notOnServer : ModelDownload.interrupted;
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
        if (await part.length() != f.size) {
          await remove();
          return ModelDownload.interrupted;
        }
        await part.rename('${dir.path}${Platform.pathSeparator}${f.name}');
      }
      await File('${dir.path}${Platform.pathSeparator}$_readyMarker').writeAsString(jsonEncode(manifest));
      onProgress?.call(1);
      final ok = await isInstalled();
      notifyListeners();
      return ok ? ModelDownload.installed : ModelDownload.interrupted;
    } catch (e) {
      debugPrint('[ModelPack:$pack] download failed: ${e.runtimeType}');
      await remove();
      if (_isOutOfSpace(e)) return ModelDownload.noSpace;
      return gotManifest ? ModelDownload.interrupted : ModelDownload.serverAway;
    } finally {
      client.close(force: true);
    }
  }

  /// A full phone: "no space left on device" (28 on Android and Linux) or "disk full" (112 on Windows).
  static bool _isOutOfSpace(Object e) {
    if (e is! FileSystemException) return false;
    final code = e.osError?.errorCode;
    return code == 28 || code == 112;
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
