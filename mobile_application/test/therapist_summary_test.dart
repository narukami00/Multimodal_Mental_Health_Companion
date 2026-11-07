import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/export/image_pdf.dart';
import 'package:solace_mobile/domain/export/therapist_summary.dart';
import 'package:solace_mobile/domain/goals/goals.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/profile/therapist_summary_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/services/data_ownership.dart';

SessionRecord _entry(DateTime at, {String? mood, String text = 'a quiet day', CaptureMode mode = CaptureMode.text}) =>
    SessionRecord(id: '${at.microsecondsSinceEpoch}', createdAt: at, mode: mode, text: text, mood: mood, emotionResults: const []);

SuggestionRecord _idea(DateTime at, {String? before, String? after, bool done = true}) => SuggestionRecord(
  id: '${at.microsecondsSinceEpoch}',
  activityId: 'a',
  shownAt: at,
  contextTags: const [],
  status: SuggestionStatus.completed,
  done: done,
  completedAt: at,
  moodBefore: before,
  moodAfter: after,
);

DailyFeatures _row(String day, {int screen = 200, int pickups = 50}) =>
    DailyFeatures(dayKey: day, sources: {'usage', 'usageFinal'}, screenOnMinutes: screen, unlockCount: pickups);

class _Files implements BackupFiles {
  String? name;
  Uint8List? bytes;

  @override
  Future<bool> save(String n, Uint8List b) async {
    name = n;
    bytes = b;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => null;

  @override
  Future<void> restart() async {}
}

class _NoLibrary implements ActivityLibraryRepository {
  @override
  Future<List<Activity>> load() async => const [];
}

void main() {
  final now = DateTime(2026, 11, 20, 12);

  group('what goes on the page', () {
    TherapistSummary make({bool words = false, int days = 30, List<DailyFeatures> rows = const []}) => buildTherapistSummary(
      sessions: [
        _entry(DateTime(2026, 11, 19, 9), mood: 'Steady', text: 'a calm morning'),
        _entry(DateTime(2026, 11, 19, 21), mood: 'Tender', text: 'tired tonight', mode: CaptureMode.voice),
        _entry(DateTime(2026, 11, 10, 9), mood: 'Steady'),
        _entry(DateTime(2026, 9, 1, 9), mood: 'Wobbly', text: 'long ago'),
        _entry(DateTime(2026, 11, 18, 9)),
      ],
      ideas: [
        _idea(DateTime(2026, 11, 15), before: 'Tender', after: 'Steady'),
        _idea(DateTime(2026, 11, 16), before: 'Steady', after: 'Tender'),
        _idea(DateTime(2026, 11, 17), done: false),
        _idea(DateTime(2026, 8, 1), before: 'Tender', after: 'Bright'),
      ],
      phoneRows: rows,
      goals: const [],
      goalDays: const [],
      now: now,
      days: days,
      name: '  Sam ',
      includeWords: words,
    );

    test('counts only the period, in the person\'s plain mood words', () {
      final s = make();
      expect(s.name, 'Sam');
      expect(s.entries, 4, reason: 'the September entry is outside 30 days');
      expect(s.activeDays, 3);
      expect(s.voiceOrVideo, 1);
      expect(s.moods.map((e) => '${e.key}:${e.value}'), ['Calm:2', 'Low:1']);
      expect(s.ideasTried, 2);
      expect(s.ideasLifted, 1);
    });

    test('a longer period reaches further back', () {
      expect(make(days: 90).entries, 5);
    });

    test('the person\'s own words are left out unless they are switched on', () {
      expect(make().words, isEmpty);
      final withWords = make(words: true).words;
      expect(withWords.first.text, 'tired tonight', reason: 'newest first');
      expect(withWords.map((w) => w.text), isNot(contains('long ago')));
    });

    test('long entries are shortened', () {
      final s = buildTherapistSummary(
        sessions: [_entry(DateTime(2026, 11, 19), text: 'word ' * 200)],
        ideas: const [],
        phoneRows: const [],
        goals: const [],
        goalDays: const [],
        now: now,
        includeWords: true,
      );
      expect(s.words.single.text.length, lessThanOrEqualTo(excerptLength + 1));
      expect(s.words.single.text.endsWith('…'), isTrue);
    });

    test('phone numbers are a typical day over full days only, and absent without data', () {
      expect(make().phone, isNull);
      final s = make(
        rows: [
          _row('2026-11-17', screen: 100),
          _row('2026-11-18', screen: 200),
          _row('2026-11-19', screen: 300),
          const DailyFeatures(dayKey: '2026-11-16', sources: {'usage'}, screenOnMinutes: 900),
          _row('2026-08-01', screen: 999),
        ],
      );
      expect(s.phone!.daysRead, 3);
      expect(s.phone!.typicalScreenMinutes, 200);
    });

    test('goals say how many days were met', () {
      final goal = Goal(id: 'g', measure: GoalMeasure.pickups, target: 40, createdDay: '2026-11-01');
      final days = judgeGoals(
        goals: [goal],
        rowsByDay: {'2026-11-17': _row('2026-11-17', pickups: 30), '2026-11-18': _row('2026-11-18', pickups: 80)},
        restDays: const {},
        lastDay: '2026-11-18',
      );
      final s = buildTherapistSummary(
        sessions: const [],
        ideas: const [],
        phoneRows: const [],
        goals: [goal],
        goalDays: days,
        now: now,
        days: 7,
      );
      expect(s.goals.single.title, 'Pickups');
      expect(s.goals.single.target, 'At most 40 pickups');
      expect((s.goals.single.met, s.goals.single.judged), (1, 2));
    });
  });

  group('the PDF', () {
    test('is a well-formed one-page file whose offsets point at its objects', () {
      final rgb = Uint8List(10 * 10 * 3)..fillRange(0, 300, 255);
      final pdf = imagePdf(rgb: rgb, width: 10, height: 10);
      final text = latin1.decode(pdf);
      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text.trimRight().endsWith('%%EOF'), isTrue);
      expect(RegExp(r'/Type /Page\b').allMatches(text), hasLength(1));
      final start = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!);
      expect(text.substring(start).startsWith('xref'), isTrue);
      final offsets = RegExp(r'(\d{10}) 00000 n').allMatches(text).map((m) => int.parse(m.group(1)!)).toList();
      expect(offsets, hasLength(5));
      for (var i = 0; i < offsets.length; i++) {
        expect(text.substring(offsets[i]).startsWith('${i + 1} 0 obj'), isTrue, reason: 'object ${i + 1}');
      }
    });

    testWidgets('a real summary renders to a PDF of the whole page', (tester) async {
      final summary = buildTherapistSummary(
        sessions: [_entry(DateTime(2026, 11, 19), mood: 'Steady')],
        ideas: const [],
        phoneRows: [_row('2026-11-19')],
        goals: const [],
        goalDays: const [],
        now: now,
        includeWords: true,
        name: 'Sam',
      );
      final pdf = await tester.runAsync(() => renderSummaryPdf(summary, madeOn: now));
      final text = latin1.decode(pdf!, allowInvalid: true);
      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text, contains('/Width 1190'));
      expect(text, contains('/Height 1684'));
    });
  });

  group('the page', () {
    testWidgets('previews the page, keeps words off by default, and saves a dated PDF', (tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
      await sessions.saveSession(mode: CaptureMode.text, text: 'steady day', mood: 'Steady', at: DateTime(2026, 11, 19, 9));
      final suggestions = SuggestionController(libraryRepository: _NoLibrary(), suggestionRepository: InMemorySuggestionRepository());
      await suggestions.load();
      final profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();
      final files = _Files();

      await tester.pumpWidget(
        MaterialApp(
          home: TherapistSummaryPage(
            sessionController: sessions,
            suggestionController: suggestions,
            profileController: profile,
            files: files,
            clock: () => now,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('summary-page')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('summary-words'))).value, isFalse);

      await tester.tap(find.byKey(const ValueKey('summary-days-90')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('summary-save')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('summary-save')));
      for (var i = 0; i < 30 && files.bytes == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(files.name, 'solace-summary-2026-11-20.pdf');
      expect(latin1.decode(files.bytes!.sublist(0, 8)), startsWith('%PDF-1.4'));
      await tester.pump();
      expect(find.text('Your summary is saved.'), findsOneWidget);
    });
  });
}
