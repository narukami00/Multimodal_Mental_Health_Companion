import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/day_key.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/services/check_in_widget_service.dart';

final _now = DateTime(2026, 9, 26, 9, 0);

SessionRecord _session(DateTime at) {
  return SessionRecord(
    id: 's${at.microsecondsSinceEpoch}',
    createdAt: at,
    mode: CaptureMode.text,
    mood: 'Steady',
  );
}

void main() {
  group('widget prompt', () {
    test('invites a check-in before one has happened', () {
      expect(
        CheckInWidgetService.promptFor(
          checkedInToday: false,
          restingToday: false,
        ),
        CheckInWidgetService.notCheckedInPrompt,
      );
    });

    test('acknowledges a check-in', () {
      expect(
        CheckInWidgetService.promptFor(
          checkedInToday: true,
          restingToday: false,
        ),
        CheckInWidgetService.checkedInPrompt,
      );
    });

    test('treats rest as a completed decision', () {
      expect(
        CheckInWidgetService.promptFor(
          checkedInToday: false,
          restingToday: true,
        ),
        CheckInWidgetService.restingPrompt,
      );
    });

    test('a check-in wins over rest on the same day', () {
      expect(
        CheckInWidgetService.promptFor(
          checkedInToday: true,
          restingToday: true,
        ),
        CheckInWidgetService.checkedInPrompt,
      );
    });

    test('never mentions streaks, counts or rewards', () {
      final prompts = [
        CheckInWidgetService.notCheckedInPrompt,
        CheckInWidgetService.checkedInPrompt,
        CheckInWidgetService.restingPrompt,
      ].join(' ').toLowerCase();

      expect(prompts, isNot(contains('streak')));
      expect(prompts, isNot(contains('days')));
      expect(prompts, isNot(contains('well done')));
      expect(prompts, isNot(contains('keep it up')));
      expect(prompts, isNot(contains('missed')));
    });
  });

  group('today state', () {
    test('detects a check-in made today', () {
      expect(
        CheckInWidgetService.checkedInToday(
          [_session(_now)],
          now: _now,
        ),
        isTrue,
      );
    });

    test('ignores a check-in from yesterday', () {
      expect(
        CheckInWidgetService.checkedInToday(
          [_session(_now.subtract(const Duration(days: 1)))],
          now: _now,
        ),
        isFalse,
      );
    });

    test('is false with no history at all', () {
      expect(
        CheckInWidgetService.checkedInToday(const [], now: _now),
        isFalse,
      );
    });

    test('recognises a rest day declared today', () {
      expect(
        CheckInWidgetService.restingToday({dayKey(_now)}, now: _now),
        isTrue,
      );
      expect(
        CheckInWidgetService.restingToday(
          {dayKey(_now.subtract(const Duration(days: 1)))},
          now: _now,
        ),
        isFalse,
      );
    });
  });
}
