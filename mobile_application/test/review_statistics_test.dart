import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/domain/chat/conversation_breakdown.dart';
import 'package:solace_mobile/domain/insights/review_statistics.dart';

void main() {
  EmotionResult reading({
    required String id,
    required double valence,
    String mood = 'low or tired',
    String modelVersion = 'demo-v0',
    DateTime? timestamp,
  }) =>
      EmotionResult(
        sessionId: id,
        modality: EmotionModality.text,
        origin: EmotionOrigin.chat,
        timestamp: timestamp ?? DateTime(2026, 4, 20, 9),
        modelVersion: modelVersion,
        valence: valence,
        classes: const {'sad': 0.5, 'neutral': 0.5},
        mood: mood,
        tier: 'clear',
        pattern: 'T',
      );

  test('shift fit and contextual reason fit are tracked independently with explicit denominators', () {
    final m1 = ChatMessageRecord(
      id: 'm1',
      isUser: true,
      text: 'Just starting the morning.',
      timestamp: DateTime(2026, 4, 20, 9, 0),
      reading: reading(id: 'm1', valence: 0.4, mood: 'calm or content'),
    );
    final m2 = ChatMessageRecord(
      id: 'm2',
      isUser: true,
      text: 'School has me really stressed out.',
      timestamp: DateTime(2026, 4, 20, 9, 5),
      reading: reading(id: 'm2', valence: -0.6, mood: 'tense or upset'),
    );

    final conv = ChatConversationRecord(
      id: 'c1',
      title: 'Morning',
      createdAt: DateTime(2026, 4, 20, 9, 0),
      updatedAt: DateTime(2026, 4, 20, 9, 5),
      messages: [m1, m2],
    );

    final breakdown = ConversationBreakdown.from(conv);
    expect(breakdown.shifts.length, 1);
    final shift = breakdown.shifts.first;
    expect(shift.proposedContext, isNotNull);

    // Agree with shift, disagree with proposed reason
    final reviewed = conv.copyWith(
      shiftReviews: [
        TrajectoryShiftReview(
          shiftId: shift.shiftId,
          fromMessageId: m1.id,
          toMessageId: m2.id,
          evidenceVersion: shift.evidenceVersion,
          shiftFit: ShiftAgreement.agrees,
          reasonFit: ShiftAgreement.disagrees,
          proposedContext: shift.proposedContext,
          reviewedAt: DateTime(2026, 4, 20, 9, 10),
        ),
      ],
    );

    final roundtrip = ChatConversationRecord.fromMap(reviewed.toMap());
    expect(roundtrip.shiftReviews.length, 1);
    expect(roundtrip.shiftReviews.first.shiftFit, ShiftAgreement.agrees);
    expect(roundtrip.shiftReviews.first.reasonFit, ShiftAgreement.disagrees);

    final stats = ReviewStatistics.compute(
      sessions: const [],
      conversations: [roundtrip],
    );
    expect(stats.trajectory.shiftsTotal, 1);
    expect(stats.trajectory.shiftReviewed, 1);
    expect(stats.trajectory.shiftAgreed, 1);
    expect(stats.trajectory.shiftFitRate, 1.0);
    expect(stats.trajectory.reasonProposedTotal, 1);
    expect(stats.trajectory.reasonReviewed, 1);
    expect(stats.trajectory.reasonAgreed, 0);
    expect(stats.trajectory.reasonDisagreed, 1);
    expect(stats.trajectory.reasonFitRate, 0.0);
  });

  test('journal review statistics exclude skipped and unanswered from fitRate denominator', () {
    final r1 = reading(id: 's1', valence: -0.4);
    final r2 = reading(id: 's2', valence: 0.4, mood: 'upbeat');
    final r3 = reading(id: 's3', valence: 0.0, mood: 'calm or content');
    final r4 = reading(id: 's4', valence: -0.2);

    final sessions = [
      SessionRecord(
        id: 's1',
        createdAt: DateTime(2026, 4, 20, 9),
        mode: CaptureMode.text,
        emotionResults: [r1],
        moodReview: MoodReview.fromReading(r1, status: MoodReviewStatus.accepted),
      ),
      SessionRecord(
        id: 's2',
        createdAt: DateTime(2026, 4, 20, 10),
        mode: CaptureMode.text,
        emotionResults: [r2],
        moodReview: MoodReview.fromReading(
          r2,
          status: MoodReviewStatus.corrected,
          correctedMood: 'Steady',
        ),
      ),
      SessionRecord(
        id: 's3',
        createdAt: DateTime(2026, 4, 20, 11),
        mode: CaptureMode.text,
        emotionResults: [r3],
        moodReview: MoodReview.fromReading(r3, status: MoodReviewStatus.skipped),
      ),
      SessionRecord(
        id: 's4',
        createdAt: DateTime(2026, 4, 20, 12),
        mode: CaptureMode.text,
        emotionResults: [r4],
      ),
    ];

    final stats = ReviewStatistics.compute(
      sessions: sessions,
      conversations: const [],
    );
    expect(stats.journal.readingsTotal, 4);
    expect(stats.journal.reviewed, 2);
    expect(stats.journal.accepted, 1);
    expect(stats.journal.corrected, 1);
    expect(stats.journal.skipped, 1);
    expect(stats.journal.unanswered, 1);
    expect(stats.journal.fitRate, 0.5);
  });
}
