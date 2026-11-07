import 'dart:convert';

/// A whole copy of what Solace keeps on this phone, as one readable file the person can store anywhere and
/// load back later (on this phone or a new one).
///
/// Everything the app saves lives in its preferences (check-ins, chats, moments, the forest, choices), so a backup
/// is those entries with their types. Pure: no files, no platform, so the format can be tested on its own.
const backupFormat = 'solace-backup';

/// Bumped when the shape of the file changes in a way an older app could not read.
const backupVersion = 1;

/// One saved value with the type it must come back as.
sealed class BackupValue {
  const BackupValue();
}

class BackupString extends BackupValue {
  const BackupString(this.value);
  final String value;
}

class BackupBool extends BackupValue {
  const BackupBool(this.value);
  final bool value;
}

class BackupInt extends BackupValue {
  const BackupInt(this.value);
  final int value;
}

class BackupDouble extends BackupValue {
  const BackupDouble(this.value);
  final double value;
}

class BackupList extends BackupValue {
  const BackupList(this.value);
  final List<String> value;
}

/// A parsed backup, ready to be put back.
class Backup {
  const Backup({required this.createdAt, required this.entries});

  final DateTime? createdAt;
  final Map<String, BackupValue> entries;

  /// What the file holds, in the person's words, for the "are you sure" step. Counts are read leniently:
  /// a missing or odd entry is simply left out of the summary, it never blocks the restore.
  BackupSummary get summary => BackupSummary(
    entries: _count('sessions.records'),
    chats: _count('solace_chat_conversations_v2'),
    moments: _count('memory.moments'),
  );

  int? _count(String key) {
    final value = entries[key];
    if (value is! BackupString) return null;
    try {
      final decoded = jsonDecode(value.value);
      if (decoded is List) return decoded.length;
    } catch (_) {}
    return null;
  }
}

class BackupSummary {
  const BackupSummary({this.entries, this.chats, this.moments});

  final int? entries;
  final int? chats;
  final int? moments;

  /// "12 entries, 3 chats and 5 moments", or null when nothing could be counted.
  String? get sentence {
    String part(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final parts = <String>[
      if (entries != null && entries! > 0) part(entries!, 'entry', 'entries'),
      if (chats != null && chats! > 0) part(chats!, 'chat', 'chats'),
      if (moments != null && moments! > 0) part(moments!, 'moment', 'moments'),
    ];
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}

/// Why a file could not be used as a backup. The wording is for the person, so nothing technical shows.
enum BackupProblem { notABackup, tooNew, damaged }

class BackupParseResult {
  const BackupParseResult.ok(Backup this.backup) : problem = null;
  const BackupParseResult.failed(BackupProblem this.problem) : backup = null;

  final Backup? backup;
  final BackupProblem? problem;

  bool get isOk => backup != null;
}

/// The file's text for these saved values. Deterministic: keys are sorted, so two backups of the same
/// state are the same file.
String buildBackup({required Map<String, Object> preferences, required DateTime createdAt}) {
  final keys = preferences.keys.toList()..sort();
  final out = <String, Object?>{};
  for (final key in keys) {
    final value = preferences[key];
    if (value is String) {
      out[key] = {'t': 's', 'v': value};
    } else if (value is bool) {
      out[key] = {'t': 'b', 'v': value};
    } else if (value is int) {
      out[key] = {'t': 'i', 'v': value};
    } else if (value is double) {
      out[key] = {'t': 'd', 'v': value};
    } else if (value is List) {
      out[key] = {'t': 'l', 'v': [for (final item in value) item.toString()]};
    }
  }
  return const JsonEncoder.withIndent(' ').convert({
    'format': backupFormat,
    'version': backupVersion,
    'app': 'Solace',
    'createdAt': createdAt.toUtc().toIso8601String(),
    'preferences': out,
  });
}

/// Reads a backup. Never throws: anything unexpected is a [BackupProblem].
BackupParseResult parseBackup(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } catch (_) {
    return const BackupParseResult.failed(BackupProblem.notABackup);
  }
  if (root is! Map || root['format'] != backupFormat) {
    return const BackupParseResult.failed(BackupProblem.notABackup);
  }
  final version = root['version'];
  if (version is! int) return const BackupParseResult.failed(BackupProblem.damaged);
  if (version > backupVersion) return const BackupParseResult.failed(BackupProblem.tooNew);

  final prefs = root['preferences'];
  if (prefs is! Map) return const BackupParseResult.failed(BackupProblem.damaged);

  final entries = <String, BackupValue>{};
  for (final entry in prefs.entries) {
    final key = entry.key;
    final cell = entry.value;
    if (key is! String || key.isEmpty || cell is! Map) {
      return const BackupParseResult.failed(BackupProblem.damaged);
    }
    final v = cell['v'];
    switch (cell['t']) {
      case 's' when v is String:
        entries[key] = BackupString(v);
      case 'b' when v is bool:
        entries[key] = BackupBool(v);
      case 'i' when v is int:
        entries[key] = BackupInt(v);
      case 'd' when v is num:
        entries[key] = BackupDouble(v.toDouble());
      case 'l' when v is List && v.every((e) => e is String):
        entries[key] = BackupList(List<String>.from(v));
      default:
        return const BackupParseResult.failed(BackupProblem.damaged);
    }
  }

  DateTime? created;
  final raw = root['createdAt'];
  if (raw is String) created = DateTime.tryParse(raw)?.toLocal();
  return BackupParseResult.ok(Backup(createdAt: created, entries: entries));
}
