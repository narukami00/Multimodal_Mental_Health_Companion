import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/domain/data/data_registry.dart';
import 'package:solace_mobile/domain/export/backup.dart';
import 'package:solace_mobile/services/data_ownership.dart';

class _Files implements BackupFiles {
  Uint8List? saved;
  int restarts = 0;

  @override
  Future<bool> save(String name, Uint8List bytes) async {
    saved = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => null;

  @override
  Future<void> restart() async => restarts++;
}

void main() {
  test('every entry has a unique id and no key is claimed twice', () {
    expect({for (final e in dataRegistry) e.id}.length, dataRegistry.length);
    final seen = <String>{};
    for (final e in dataRegistry) {
      for (final k in e.keys) {
        expect(seen.add(k), isTrue, reason: '$k is declared twice');
      }
    }
  });

  test('every key the app stores is declared in the registry', () {
    // Finds `static const _key = 'x'` style declarations and direct `prefs.setString('x', ...)` calls.
    final declared = RegExp(r"""(?:static\s+)?(?:const|final)\s+(?:String\s+)?_?\w*[kK]ey\w*\s*=\s*'([^']+)'""");
    final direct = RegExp(r"""(?:prefs|preferences|_preferences|_prefs)\??\.(?:set|get|remove|containsKey)(?:String|Bool|Int|Double|StringList)?\(\s*'([a-zA-Z_][\w.]*)'""");
    final found = <String, String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('data_registry.dart')) continue;
      final text = file.readAsStringSync();
      for (final m in [...declared.allMatches(text), ...direct.allMatches(text)]) {
        // A string with interpolation is a label made on the spot, not a fixed storage key.
        if (!m.group(1)!.contains(r'$')) found[m.group(1)!] = file.path;
      }
    }
    expect(found, isNotEmpty, reason: 'the scan found nothing, so it is not looking in the right place');
    final missing = [
      for (final e in found.entries)
        if (registryEntryFor(e.key) == null) '${e.key} (${e.value})',
    ];
    expect(
      missing,
      isEmpty,
      reason: 'Stored but not declared in lib/domain/data/data_registry.dart. Add an entry so it is saved in a copy, '
          'erased with everything else, and considered for the therapist summary.',
    );
  });

  test('anything undeclared is kept in a copy rather than dropped', () {
    expect(keyInBackup('some.new.feature'), isTrue);
    expect(keyInBackup('companion_server_host'), isFalse);
    expect(keyInBackup('sessions.records'), isTrue);
  });

  group('copies and the registry', () {
    late _Files files;
    late DataOwnership service;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'sessions.records': jsonEncode([{}]),
        'companion_server_host': '100.1.2.3',
        'checkin_prompt': 'How are you?',
        'unlisted.thing': 'kept',
      });
      files = _Files();
      service = DataOwnership(
        files: files,
        recordingsDirectory: () async => Directory.systemTemp.createTemp('solace_reg'),
        stopReminders: () async {},
      );
    });

    test('a copy leaves out what belongs to this phone', () async {
      await service.exportBackup();
      final copy = parseBackup(utf8.decode(files.saved!)).backup!;
      expect(copy.entries.keys, containsAll(['sessions.records', 'unlisted.thing']));
      expect(copy.entries.keys, isNot(contains('companion_server_host')));
      expect(copy.entries.keys, isNot(contains('checkin_prompt')));
    });

    test('bringing a copy back keeps this phone\'s own settings', () async {
      final copy = parseBackup(buildBackup(preferences: {'sessions.records': '[]', 'companion_server_host': 'other'}, createdAt: DateTime(2026)))
          .backup!;
      await service.restore(copy);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('companion_server_host'), '100.1.2.3', reason: 'the phone keeps its own server address');
      expect(prefs.getString('sessions.records'), '[]');
      expect(prefs.containsKey('unlisted.thing'), isFalse, reason: 'what a copy would hold is replaced');
    });
  });
}
