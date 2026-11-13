import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/domain/chat/conversation_breakdown.dart';
import 'package:solace_mobile/features/chat/shift_review_list.dart';

MoodShift _makeShift({
  required String idPrefix,
  required String text,
  String? proposedContext,
}) {
  final ts = DateTime(2026, 10, 5, 19);
  final fromReading = EmotionResult(
    sessionId: 'c1',
    timestamp: ts,
    modality: EmotionModality.text,
    valence: 0.2,
    arousal: 0.2,
    mood: 'calm or content',
    tier: 'hint',
    pattern: 'T',
    modelVersion: 'emotion-v0',
  );
  final toReading = EmotionResult(
    sessionId: 'c1',
    timestamp: ts.add(const Duration(minutes: 2)),
    modality: EmotionModality.text,
    valence: -0.6,
    arousal: 0.3,
    mood: 'low or tired',
    tier: 'clear',
    pattern: 'T',
    modelVersion: 'emotion-v0',
  );
  return MoodShift(
    from: ReadMessage(
      ChatMessageRecord(
        id: '${idPrefix}_m1',
        isUser: true,
        text: 'Earlier was fine.',
        timestamp: ts,
        reading: fromReading,
      ),
      fromReading,
    ),
    to: ReadMessage(
      ChatMessageRecord(
        id: '${idPrefix}_m2',
        isUser: true,
        text: text,
        timestamp: ts.add(const Duration(minutes: 2)),
        reading: toReading,
      ),
      toReading,
    ),
    proposedContext: proposedContext,
  );
}

void main() {
  testWidgets(
    'ShiftsReviewList starts collapsed, expands one shift at a time, and advances',
    (tester) async {
      final s1 = _makeShift(
        idPrefix: 's1',
        text: 'Midterm pressure hit all at once.',
        proposedContext: 'Work or study',
      );
      final s2 = _makeShift(
        idPrefix: 's2',
        text: 'Sleep has been tough this week.',
      );

      final reviews = <TrajectoryShiftReview>[];

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ShiftsReviewList(
                  shifts: [s1, s2],
                  reviews: reviews,
                  onSaveReview: (r) => setState(() {
                    reviews.removeWhere((e) => e.shiftId == r.shiftId);
                    reviews.add(r);
                  }),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('0 of 2 reviewed'), findsOneWidget);
      expect(find.text('Did it feel like a shift here?'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('shifts-review-next')));
      await tester.pumpAndSettle();

      expect(find.text('Did it feel like a shift here?'), findsOneWidget);
      expect(find.text('Possible context: Work or study'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('shift-fit-${s1.shiftId}-agrees')));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 reviewed'), findsOneWidget);
      expect(find.text('Fits'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('reason-fit-${s1.shiftId}-agrees')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next shift'));
      await tester.pumpAndSettle();

      expect(find.text('Possible context: Work or study'), findsNothing);
      await tester.tap(find.byKey(ValueKey('shift-fit-${s2.shiftId}-unsure')));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2 reviewed'), findsOneWidget);
    },
  );
}
