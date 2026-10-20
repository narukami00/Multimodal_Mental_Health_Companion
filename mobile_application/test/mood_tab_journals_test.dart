import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/day_key.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/insights/journal_breakdown.dart';
import 'package:solace_mobile/domain/insights/mood_insights.dart';
import 'package:solace_mobile/features/insights/mood_tab.dart';
import 'package:solace_mobile/features/journal/session_detail_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

final _now = DateTime(2026, 10, 31, 20);

EmotionResult _reading(String mood, {double neg = 0.2, double pos = 0.2, double low = 0.3, double high = 0.3}) =>
    EmotionResult(
      sessionId: 's',
      modality: EmotionModality.voice,
      timestamp: _now,
      modelVersion: 'test',
      mood: mood,
      tier: 'clear',
      pattern: 'AT',
      classes: const {'neutral': 1.0},
      valenceProbs: {'negative': neg, 'neutral': 1 - neg - pos, 'positive': pos},
      arousalProbs: {'low': low, 'mid': 1 - low - high, 'high': high},
    );

SessionRecord _entry(String id, int day, int hour, CaptureMode mode, {String? picked, EmotionResult? r, String? text}) =>
    SessionRecord(
      id: id,
      createdAt: DateTime(2026, 10, day, hour),
      mode: mode,
      text: text ?? 'words of $id',
      mood: picked,
      emotionResults: r == null ? const [] : [r],
    );

void main() {
  // 30 Oct: three entries, three different readings. 28 Oct: one older entry with only a picked word.
  final records = [
    _entry('a', 30, 9, CaptureMode.text, r: _reading('low or tired', neg: 0.7, pos: 0.1, low: 0.6, high: 0.1)),
    _entry('b', 30, 13, CaptureMode.voice, r: _reading('calm or content', neg: 0.1, pos: 0.6)),
    _entry('c', 30, 18, CaptureMode.video, r: _reading('tense or upset', neg: 0.8, pos: 0.05, low: 0.1, high: 0.7)),
    _entry('d', 28, 10, CaptureMode.text, picked: 'bright'),
    SessionRecord(
      id: 'e',
      createdAt: DateTime(2026, 9, 20, 10), // outside the 30 days
      mode: CaptureMode.text,
      text: 'long ago',
      mood: 'steady',
    ),
  ];

  group('the day model', () {
    test('keeps every entry of a day in order, not only the top word', () {
      final strip = moodStrip(records, _now);
      final day = strip.firstWhere((d) => d.day == DateTime(2026, 10, 30));
      expect(day.entries.map((e) => e.id), ['a', 'b', 'c']);
      expect(day.moods, ['Tender', 'Steady', 'Wobbly']);
      expect(strip.firstWhere((d) => d.day == DateTime(2026, 10, 29)).entries, isEmpty);
    });
  });

  group('the journal breakdown', () {
    test('counts kinds and moods in the window only, and averages what the model read', () {
      final b = JournalBreakdown.from(records, _now);
      expect(b.total, 4);
      expect(b.byMode[CaptureMode.text], 2);
      expect(b.byMode[CaptureMode.voice], 1);
      expect(b.byMode[CaptureMode.video], 1);
      expect(b.read, 4);
      expect(b.moodCounts, {'Upbeat': 1, 'Calm': 1, 'Even': 0, 'Low': 1, 'Tense': 1});
      expect(b.averageScore, isNotNull); // from the three model readings only
      expect(b.leaning, isNotNull);
      expect(b.leanByMode[CaptureMode.text], isNull); // two entries, two different words: a tie says nothing
    });

    test('says what a kind of entry leans toward only when it is clear', () {
      final more = [
        _entry('1', 30, 9, CaptureMode.voice, r: _reading('low or tired')),
        _entry('2', 30, 10, CaptureMode.voice, r: _reading('low or tired')),
        _entry('3', 30, 11, CaptureMode.voice, r: _reading('calm or content')),
      ];
      final b = JournalBreakdown.from(more, _now);
      expect(b.leanByMode[CaptureMode.voice], 'Low');
      expect(b.leanByMode[CaptureMode.video], isNull);
      expect(b.dominantWord, 'Low');
    });

    test('with nothing in the window it is empty', () {
      expect(JournalBreakdown.from([records.last], _now).isEmpty, isTrue);
    });
  });

  group('on the Insights mood tab', () {
    Future<SessionController> controller() async {
      final repo = InMemorySessionRepository();
      for (final r in records) {
        await repo.save(r);
      }
      final c = SessionController(repository: repo, emotionAnalyzer: const MockEmotionAnalyzer());
      await c.load();
      return c;
    }

    Future<void> pump(WidgetTester tester, SessionController c) async {
      tester.view.physicalSize = const Size(1080, 4800);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MoodTab(sessionController: c, clock: () => _now))),
      ));
      await tester.pump(const Duration(milliseconds: 900));
    }

    testWidgets('a day with several entries opens a list of them with kind, time and mood', (tester) async {
      final c = await controller();
      await pump(tester, c);

      final key = ValueKey('mood-day-${dayKey(DateTime(2026, 10, 30))}');
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-day-sheet')), findsOneWidget);
      expect(find.text('3 entries, in the order you made them'), findsOneWidget);
      expect(find.textContaining('Text ·'), findsOneWidget);
      expect(find.textContaining('Voice ·'), findsOneWidget);
      expect(find.textContaining('Video ·'), findsOneWidget);
      expect(find.text('Low'), findsWidgets);
      expect(find.text('Tense'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('mood-day-entry-c')));
      await tester.pumpAndSettle();
      expect(find.byType(SessionDetailPage), findsOneWidget);
    });

    testWidgets('an empty day does nothing when tapped, and the breakdown card shows counts per kind', (tester) async {
      final c = await controller();
      await pump(tester, c);

      await tester.tap(find.byKey(ValueKey('mood-day-${dayKey(DateTime(2026, 10, 29))}')), warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('mood-day-sheet')), findsNothing);

      expect(find.byKey(const ValueKey('journal-breakdown')), findsOneWidget);
      expect(find.text('4 entries in the last 30 days'), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-mode-text')), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-mode-voice')), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-mode-video')), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-mood-bar')), findsOneWidget);
    });
  });
}
