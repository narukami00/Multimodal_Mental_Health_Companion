import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/constants/moods.dart';
import 'package:solace_mobile/core/models/break_annotation.dart';
import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/personalization/personal_calibration.dart';
import 'package:solace_mobile/features/journal/emotion_reading_card.dart';

EmotionResult _reading(String id, {String? mood = 'calm or content'}) =>
    EmotionResult(
      sessionId: id,
      modality: EmotionModality.voice,
      timestamp: DateTime(2026, 11, 10, 12),
      modelVersion: 'v1',
      confidence: 0.72,
      mood: mood,
      classes: const {'neutral': 0.7, 'joy': 0.2},
    );

SessionRecord _reviewedSession(
  String id, {
  required String? readingMood,
  required MoodReviewStatus status,
  String? correctedMood,
}) {
  final reading = _reading(id, mood: readingMood);
  return SessionRecord(
    id: id,
    createdAt: DateTime(2026, 11, 10, 12),
    mode: CaptureMode.voice,
    emotionResults: [reading],
    moodReview: MoodReview.fromReading(
      reading,
      status: status,
      correctedMood: correctedMood,
      reviewedAt: DateTime(2026, 11, 10, 12, 5),
    ),
  );
}

void main() {
  test('calibration stays inactive below minReviewsForCalibration (5)', () {
    final sessions = [
      for (var i = 0; i < 4; i++)
        _reviewedSession(
          's$i',
          readingMood: 'calm or content',
          status: MoodReviewStatus.corrected,
          correctedMood: 'Wobbly',
        ),
    ];

    final profile = PersonalPatternProfile.from(sessions: sessions);
    expect(profile.totalReviewedMoods, 4);
    expect(profile.isCalibrated, isFalse);
    expect(profile.calibrationFor(_reading('new')), isNull);
  });

  test('learns personal pattern at >= 5 reviews without mutating raw reading', () {
    final sessions = [
      for (var i = 0; i < 4; i++)
        _reviewedSession(
          's$i',
          readingMood: 'calm or content',
          status: MoodReviewStatus.corrected,
          correctedMood: 'Wobbly',
        ),
      _reviewedSession(
        's4',
        readingMood: 'upbeat',
        status: MoodReviewStatus.accepted,
      ),
    ];

    final targetReading = _reading('target', mood: 'calm or content');
    final profile = PersonalPatternProfile.from(sessions: sessions);

    expect(profile.isCalibrated, isTrue);
    expect(profile.totalReviewedMoods, 5);

    final rule = profile.calibrationFor(targetReading);
    expect(rule, isNotNull);
    expect(rule!.preferredMood, 'Wobbly');
    expect(rule.correctedCount, 4);
    expect(rule.totalForBucket, 4);

    // Raw EmotionResult remains completely untouched.
    expect(targetReading.mood, 'calm or content');

    // Ranked correction pills place learned preference first, preserving all moods.
    final ranked = profile.rankedMoodChoices(targetReading);
    expect(ranked.first, 'Wobbly');
    expect(ranked.toSet(), Moods.values.toSet());
  });

  test('ignores skipped reviews and requires strict majority per bucket', () {
    final sessions = [
      for (var i = 0; i < 3; i++)
        _reviewedSession(
          'c$i',
          readingMood: 'calm or content',
          status: MoodReviewStatus.corrected,
          correctedMood: 'Tender',
        ),
      for (var i = 0; i < 3; i++)
        _reviewedSession(
          'a$i',
          readingMood: 'calm or content',
          status: MoodReviewStatus.accepted,
        ),
      for (var i = 0; i < 5; i++)
        _reviewedSession(
          'sk$i',
          readingMood: 'low or tired',
          status: MoodReviewStatus.skipped,
        ),
    ];

    final profile = PersonalPatternProfile.from(sessions: sessions);
    expect(profile.totalReviewedMoods, 6);
    expect(profile.calibrationFor(_reading('r1', mood: 'calm or content')), isNull);
    expect(profile.calibrationFor(_reading('r2', mood: 'low or tired')), isNull);
  });

  test('aggregates confirmed shift contexts, helpful tags, and fresh pulse safely', () {
    final conv = ChatConversationRecord(
      id: 'c1',
      title: 'Evening chat',
      createdAt: DateTime(2026, 11, 10, 18),
      updatedAt: DateTime(2026, 11, 10, 19),
      messages: [
        ChatMessageRecord(
          id: 'm1',
          isUser: true,
          text: 'Feeling overwhelmed.',
          timestamp: DateTime(2026, 11, 10, 18),
        ),
      ],
      shiftReviews: [
        TrajectoryShiftReview(
          shiftId: 'sh1',
          fromMessageId: 'm1',
          toMessageId: 'm2',
          evidenceVersion: 'v1',
          reviewedAt: DateTime(2026, 11, 10, 19),
          shiftFit: ShiftAgreement.agrees,
          proposedContext: 'Work or study',
          reasonFit: ShiftAgreement.agrees,
        ),
        TrajectoryShiftReview(
          shiftId: 'sh2',
          fromMessageId: 'm2',
          toMessageId: 'm3',
          evidenceVersion: 'v1',
          reviewedAt: DateTime(2026, 11, 10, 19),
          shiftFit: ShiftAgreement.disagrees,
          proposedContext: 'Sleep',
          reasonFit: ShiftAgreement.agrees,
        ),
      ],
    );

    final ann = BreakAnnotation(
      breakKey: '2026-11-10',
      status: BreakAnnotationStatus.answered,
      shownAt: DateTime(2026, 11, 10, 10),
      decidedAt: DateTime(2026, 11, 10, 10, 5),
      theme: 'work',
    );

    final suggestions = [
      SuggestionRecord(
        id: 'sg1',
        activityId: 'act1',
        shownAt: DateTime(2026, 11, 10, 14),
        status: SuggestionStatus.completed,
        done: true,
        useful: SuggestionUsefulness.up,
        contextTags: const ['breathe', 'unknown_secret_tag'],
      ),
    ];

    final now = DateTime(2026, 11, 11, 12);
    final profile = PersonalPatternProfile.from(
      sessions: const [],
      conversations: [conv],
      breakAnnotations: [ann],
      suggestions: suggestions,
      latestPulse: LifePulseSignal(
        moodTag: 'stressed',
        at: now.subtract(const Duration(hours: 4)),
        note: 'big deadline\ntonight',
      ),
    );

    expect(profile.recurringShiftContexts.length, 1);
    expect(profile.recurringShiftContexts.first.context, 'Work or study');
    expect(profile.recurringShiftContexts.first.count, 2);
    expect(profile.helpfulTags, ['breathing exercises']);

    final phrases = profile.safePersonalizationPhrases(now: now);
    expect(phrases.length, 3);
    expect(phrases[0], contains('big deadline tonight'));
    expect(phrases[0], isNot(contains('\n')));
    expect(phrases[1], contains('work or study'));
    expect(phrases[2], contains('breathing exercises'));
  });

  testWidgets('EmotionReadingCard renders personal hint and reorders choices', (
    tester,
  ) async {
    final sessions = [
      for (var i = 0; i < 4; i++)
        _reviewedSession(
          's$i',
          readingMood: 'calm or content',
          status: MoodReviewStatus.corrected,
          correctedMood: 'Wobbly',
        ),
      _reviewedSession(
        's4',
        readingMood: 'upbeat',
        status: MoodReviewStatus.accepted,
      ),
    ];
    final profile = PersonalPatternProfile.from(sessions: sessions);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EmotionReadingCard(
              reading: _reading('cur', mood: 'calm or content'),
              personalization: profile,
              onReview: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('reading-personal-hint')), findsOneWidget);
    expect(find.textContaining('usually call this tense'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reading-fit-not-quite')));
    await tester.pumpAndSettle();

    final firstChipX = tester.getTopLeft(find.byKey(const ValueKey('reading-mood-wobbly'))).dx;
    final steadyChipX = tester.getTopLeft(find.byKey(const ValueKey('reading-mood-steady'))).dx;
    expect(firstChipX, lessThan(steadyChipX));
  });
}
