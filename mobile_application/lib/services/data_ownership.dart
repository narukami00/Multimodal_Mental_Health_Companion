import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/export/backup.dart';
import 'check_in_reminder_service.dart';

/// Where a backup file goes to and comes from. Android's own document picker, so the person chooses the place
/// (their files, Drive, a USB stick) and Solace never needs storage permission or an internet connection.
abstract class BackupFiles {
  /// Offers [bytes] to be saved as [name]. False when the person backs out or the phone refuses.
  Future<bool> save(String name, Uint8List bytes);

  /// Lets the person pick a file; null when they back out.
  Future<Uint8List?> pick();

  /// Closes the app and opens it again, so everything starts from what is now stored.
  Future<void> restart();
}

class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles();

  static const _channel = MethodChannel('com.sysmentalhealth.solace_mobile/file_transfer');

  @override
  Future<bool> save(String name, Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<bool>('save', {'name': name, 'bytes': bytes}) ?? false;
    } catch (error) {
      debugPrint('[Backup] save failed: ${error.runtimeType}');
      return false;
    }
  }

  @override
  Future<Uint8List?> pick() async {
    try {
      return await _channel.invokeMethod<Uint8List>('pick');
    } catch (error) {
      debugPrint('[Backup] pick failed: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> restart() async {
    try {
      await _channel.invokeMethod<void>('restart');
    } catch (error) {
      debugPrint('[Backup] restart failed: ${error.runtimeType}');
    }
  }
}

enum SaveOutcome { saved, cancelled }

/// What picking a backup gave: a file ready to restore, nothing (the person backed out), or a reason.
class PickedBackup {
  const PickedBackup.ready(Backup this.backup) : problem = null;
  const PickedBackup.cancelled() : backup = null, problem = null;
  const PickedBackup.rejected(BackupProblem this.problem) : backup = null;

  final Backup? backup;
  final BackupProblem? problem;

  bool get isCancelled => backup == null && problem == null;
}

/// Taking everything out, putting it back, and erasing it: the person's data is theirs.
class DataOwnership {
  DataOwnership({
    Future<SharedPreferences> Function()? preferences,
    BackupFiles? files,
    Future<Directory> Function()? recordingsDirectory,
    Future<void> Function()? stopReminders,
    DateTime Function()? now,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       files = files ?? const PlatformBackupFiles(),
       _recordingsDirectory = recordingsDirectory ?? _defaultRecordings,
       _stopReminders = stopReminders ?? CheckInReminderService.instance.cancel,
       _now = now ?? DateTime.now;

  static final DataOwnership instance = DataOwnership();

  final Future<SharedPreferences> Function() _preferences;
  final BackupFiles files;
  final Future<Directory> Function() _recordingsDirectory;
  final Future<void> Function() _stopReminders;
  final DateTime Function() _now;

  static Future<Directory> _defaultRecordings() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}pending_recordings');
  }

  /// The name a backup is offered under, e.g. `solace-backup-2026-11-07.json`.
  String fileName() {
    final d = _now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'solace-backup-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  Future<String> backupText() async {
    final prefs = await _preferences();
    await prefs.reload();
    return buildBackup(
      preferences: {for (final key in prefs.getKeys()) key: prefs.get(key)!},
      createdAt: _now(),
    );
  }

  /// Offers a full copy to be saved wherever the person likes.
  Future<SaveOutcome> exportBackup() async {
    final text = await backupText();
    final saved = await files.save(fileName(), Uint8List.fromList(utf8.encode(text)));
    return saved ? SaveOutcome.saved : SaveOutcome.cancelled;
  }

  /// Lets the person pick a backup and checks it. Nothing is changed yet.
  Future<PickedBackup> pickBackup() async {
    final bytes = await files.pick();
    if (bytes == null) return const PickedBackup.cancelled();
    final String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      return const PickedBackup.rejected(BackupProblem.notABackup);
    }
    final result = parseBackup(text);
    final backup = result.backup;
    return backup == null ? PickedBackup.rejected(result.problem!) : PickedBackup.ready(backup);
  }

  /// Replaces everything on this phone with the backup, then restarts so every screen reads the restored data.
  Future<void> restore(Backup backup) async {
    final prefs = await _preferences();
    await prefs.clear();
    for (final entry in backup.entries.entries) {
      switch (entry.value) {
        case BackupString(:final value):
          await prefs.setString(entry.key, value);
        case BackupBool(:final value):
          await prefs.setBool(entry.key, value);
        case BackupInt(:final value):
          await prefs.setInt(entry.key, value);
        case BackupDouble(:final value):
          await prefs.setDouble(entry.key, value);
        case BackupList(:final value):
          await prefs.setStringList(entry.key, value);
      }
    }
    await _deleteRecordings();
    await _stopReminders();
    await files.restart();
  }

  /// Erases everything Solace keeps on this phone, then restarts into a fresh start.
  /// The downloaded models are not the person's data and stay (they can be removed in Permissions & privacy).
  Future<void> eraseEverything() async {
    final prefs = await _preferences();
    await prefs.clear();
    await _deleteRecordings();
    await _stopReminders();
    await files.restart();
  }

  Future<void> _deleteRecordings() async {
    try {
      final dir = await _recordingsDirectory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (error) {
      debugPrint('[Backup] could not clear recordings: ${error.runtimeType}');
    }
  }
}
