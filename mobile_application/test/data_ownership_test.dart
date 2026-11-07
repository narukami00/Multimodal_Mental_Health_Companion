import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/export/backup.dart';
import 'package:solace_mobile/features/profile/data_ownership_section.dart';
import 'package:solace_mobile/services/data_ownership.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFiles implements BackupFiles {
  Uint8List? saved;
  String? savedName;
  Uint8List? toPick;
  bool saveAccepted = true;
  int restarts = 0;

  @override
  Future<bool> save(String name, Uint8List bytes) async {
    if (!saveAccepted) return false;
    savedName = name;
    saved = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => toPick;

  @override
  Future<void> restart() async => restarts++;
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  final created = DateTime.utc(2026, 11, 7, 10);

  group('backup format', () {
    test('round-trips every kind of value', () {
      final text = buildBackup(
        preferences: {
          'a.string': 'hello',
          'b.bool': true,
          'c.int': 7,
          'd.double': 1.5,
          'e.list': ['x', 'y'],
        },
        createdAt: created,
      );
      final parsed = parseBackup(text).backup!;
      expect((parsed.entries['a.string'] as BackupString).value, 'hello');
      expect((parsed.entries['b.bool'] as BackupBool).value, isTrue);
      expect((parsed.entries['c.int'] as BackupInt).value, 7);
      expect((parsed.entries['d.double'] as BackupDouble).value, 1.5);
      expect((parsed.entries['e.list'] as BackupList).value, ['x', 'y']);
      expect(parsed.createdAt!.toUtc(), created);
    });

    test('is deterministic whatever order the keys arrive in', () {
      final one = buildBackup(preferences: {'b': 1, 'a': 2}, createdAt: created);
      final two = buildBackup(preferences: {'a': 2, 'b': 1}, createdAt: created);
      expect(one, two);
    });

    test('summarises what it holds, leniently', () {
      final text = buildBackup(
        preferences: {
          'sessions.records': jsonEncode([{}, {}, {}]),
          'solace_chat_conversations_v2': jsonEncode([{}]),
          'memory.moments': 'not json at all',
        },
        createdAt: created,
      );
      final summary = parseBackup(text).backup!.summary;
      expect(summary.sentence, '3 entries and 1 chat');
    });

    test('refuses what is not a backup, is from the future, or is damaged', () {
      expect(parseBackup('hello').problem, BackupProblem.notABackup);
      expect(parseBackup('{"format":"other"}').problem, BackupProblem.notABackup);
      expect(
        parseBackup('{"format":"solace-backup","version":99,"preferences":{}}').problem,
        BackupProblem.tooNew,
      );
      expect(
        parseBackup('{"format":"solace-backup","version":1,"preferences":{"k":{"t":"i","v":"nope"}}}').problem,
        BackupProblem.damaged,
      );
      expect(parseBackup('{"format":"solace-backup","version":1}').problem, BackupProblem.damaged);
    });
  });

  group('DataOwnership', () {
    late _FakeFiles files;
    late Directory recordings;
    late int reminderStops;
    late DataOwnership service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'sessions.records': jsonEncode([{}, {}]),
        'profile.flag': true,
        'forest_v1': '{}',
      });
      files = _FakeFiles();
      recordings = await Directory.systemTemp.createTemp('solace_rec');
      File('${recordings.path}/1.pcm').writeAsBytesSync([1, 2, 3]);
      reminderStops = 0;
      service = DataOwnership(
        files: files,
        recordingsDirectory: () async => recordings,
        stopReminders: () async => reminderStops++,
        now: () => DateTime(2026, 11, 7, 9),
      );
    });

    tearDown(() async {
      if (await recordings.exists()) await recordings.delete(recursive: true);
    });

    test('exports everything under a dated name', () async {
      expect(await service.exportBackup(), SaveOutcome.saved);
      expect(files.savedName, 'solace-backup-2026-11-07.json');
      final parsed = parseBackup(utf8.decode(files.saved!)).backup!;
      expect(parsed.entries.keys, containsAll(['sessions.records', 'profile.flag', 'forest_v1']));
    });

    test('a cancelled save says so', () async {
      files.saveAccepted = false;
      expect(await service.exportBackup(), SaveOutcome.cancelled);
    });

    test('picking changes nothing, and rejects the wrong file', () async {
      expect((await service.pickBackup()).isCancelled, isTrue);
      files.toPick = _bytes('just some text');
      expect((await service.pickBackup()).problem, BackupProblem.notABackup);
      files.toPick = Uint8List.fromList([0xff, 0xfe, 0xfd]);
      expect((await service.pickBackup()).problem, BackupProblem.notABackup);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('profile.flag'), isTrue);
    });

    test('restore replaces what is there, clears recordings and restarts', () async {
      final text = buildBackup(preferences: {'only.in.backup': 'yes', 'count': 3}, createdAt: created);
      files.toPick = _bytes(text);
      final picked = await service.pickBackup();
      await service.restore(picked.backup!);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('only.in.backup'), 'yes');
      expect(prefs.getInt('count'), 3);
      expect(prefs.containsKey('profile.flag'), isFalse);
      expect(recordings.existsSync(), isFalse);
      expect(reminderStops, 1);
      expect(files.restarts, 1);
    });

    test('erase leaves nothing and restarts', () async {
      await service.eraseEverything();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(recordings.existsSync(), isFalse);
      expect(reminderStops, 1);
      expect(files.restarts, 1);
    });
  });

  group('DataOwnershipSection', () {
    late _FakeFiles files;
    late DataOwnership service;

    Future<void> mount(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'sessions.records': jsonEncode([{}, {}, {}])});
      files = _FakeFiles();
      service = DataOwnership(
        files: files,
        recordingsDirectory: () async => Directory.systemTemp.createTemp('solace_rec'),
        stopReminders: () async {},
        now: () => DateTime(2026, 11, 7),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: DataOwnershipSection(service: service))),
        ),
      );
    }

    testWidgets('saving a copy confirms in words', (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('data-export')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(files.saved, isNotNull);
      expect(find.text('Your copy is saved.'), findsOneWidget);
    });

    testWidgets('a wrong file is explained and nothing changes', (tester) async {
      await mount(tester);
      files.toPick = _bytes('not a backup');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('data-import')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('That file is not a Solace copy.'), findsOneWidget);
      expect(files.restarts, 0);
    });

    testWidgets('bringing a copy back asks first, naming what it holds', (tester) async {
      await mount(tester);
      files.toPick = _bytes(
        buildBackup(preferences: {'sessions.records': jsonEncode([{}, {}])}, createdAt: DateTime.utc(2026, 3, 2, 12)),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('data-import')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('2 entries'), findsOneWidget);
      expect(files.restarts, 0);

      await tester.tap(find.byKey(const ValueKey('import-confirm')));
      // The restore alternates between the phone's file system (real time) and the app (fake time).
      for (var i = 0; i < 40 && files.restarts == 0; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump();
      expect(files.restarts, 1);
    });

    testWidgets('erase asks first and keeps everything on "Keep my data"', (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('data-erase')));
      await tester.pumpAndSettle();
      expect(find.text('Erase everything?'), findsOneWidget);
      await tester.tap(find.text('Keep my data'));
      await tester.pumpAndSettle();
      expect(files.restarts, 0);
    });

    testWidgets('erase wipes after the confirm', (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('data-erase')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('erase-confirm')));
      // The erase alternates between the phone's file system (real time) and the app (fake time).
      for (var i = 0; i < 40 && files.restarts == 0; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump();
      expect(files.restarts, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
