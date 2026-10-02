import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/domain/footprint/phone_noticings.dart';

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

final _now = DateTime(2026, 10, 31, 9);

/// [count] finished days ending the day before [_now].
List<DailyFeatures> _days(
  int count, {
  int Function(DateTime day)? screen,
  Map<String, int>? categories,
  bool sleep = true,
  bool final_ = true,
}) => [
  for (var back = count; back >= 1; back--)
    () {
      final day = DateTime(2026, 10, 31 - back);
      final weekend = {DateTime.friday, DateTime.saturday}.contains(day.weekday);
      return DailyFeatures(
        dayKey: _key(day),
        sources: {'usage', if (final_) 'usageFinal'},
        screenOnMinutes: screen?.call(day) ?? (weekend ? 300 : 200),
        categoryMinutes: categories ?? const {'social': 90, 'messaging': 30, 'video': 20},
        estimatedSleepStartMinute: sleep ? 23 * 60 + 30 : null,
        estimatedSleepEndMinute: sleep ? 7 * 60 : null,
        estimatedSleepMinutes: sleep ? 450 : null,
      );
    }(),
];

void main() {
  group('while it is still learning', () {
    test('says only how many days have been read', () {
      final result = phoneNoticings(_days(9), _now);

      expect(result.isLearning, isTrue);
      expect(result.daysRead, 9);
      expect(result.daysNeeded, 14);
      expect(result.noticings, isEmpty);
    });

    test('nothing read is empty, not learning a number', () {
      final result = phoneNoticings(const [], _now);

      expect(result.isEmpty, isTrue);
      expect(result.noticings, isEmpty);
    });

    test('days read before they ended, today, and in-app-only days do not count', () {
      final rows = [
        ..._days(10),
        ..._days(5, final_: false).map(
          (r) => DailyFeatures(
            dayKey: '2026-09-${(r.dayKey.substring(8)).padLeft(2, '0')}',
            sources: const {'usage'},
            screenOnMinutes: 500,
          ),
        ),
        DailyFeatures(
          dayKey: _key(_now),
          sources: const {'usage', 'usageFinal'},
          screenOnMinutes: 999,
        ),
        const DailyFeatures(dayKey: '2026-10-01', sources: {'inApp'}, checkInCount: 2),
      ];

      expect(phoneNoticings(rows, _now).daysRead, 10);
    });
  });

  group('once it knows what is usual', () {
    test('describes usual screen time, split when weekends clearly differ', () {
      final result = phoneNoticings(_days(28), _now);

      expect(result.isLearning, isFalse);
      final screen = result.noticings.firstWhere((n) => n.kind == NoticingKind.screen);
      expect(
        screen.text,
        'Your screen is usually on for about 3 h 20 min on a weekday and about '
        '5 h on a weekend day.',
      );
      expect(screen.meta, 'YOUR USUAL SCREEN TIME');
    });

    test('is one number when weekdays and weekends are alike', () {
      final result = phoneNoticings(_days(28, screen: (_) => 200), _now);

      final screen = result.noticings.firstWhere((n) => n.kind == NoticingKind.screen);
      expect(screen.text, 'Your screen is usually on for about 3 h 20 min a day.');
    });

    test('describes the usual night and how steady it is', () {
      final result = phoneNoticings(_days(28), _now);

      final night = result.noticings.firstWhere((n) => n.kind == NoticingKind.rhythm);
      expect(
        night.text,
        'Your phone usually goes down around 11:30 PM and is next picked up '
        'around 7:00 AM. The time it goes down has been very steady.',
      );
    });

    test('gives the spread in minutes when the night has varied', () {
      final rows = [
        for (final row in _days(28))
          DailyFeatures(
            dayKey: row.dayKey,
            sources: row.sources,
            screenOnMinutes: row.screenOnMinutes,
            categoryMinutes: row.categoryMinutes,
            estimatedSleepStartMinute:
                row.dayKey.hashCode.isEven ? 22 * 60 + 30 : 23 * 60 + 30,
            estimatedSleepEndMinute: 7 * 60,
            estimatedSleepMinutes: 450,
          ),
      ];

      final night = phoneNoticings(rows, _now).noticings
          .firstWhere((n) => n.kind == NoticingKind.rhythm);

      expect(night.text, contains('has varied by about'));
      expect(night.text, matches(RegExp(r'about \d+ min\.$')));
    });

    test('leaves out the night when there is no sleep estimate', () {
      final result = phoneNoticings(_days(28, sleep: false), _now);

      expect(result.noticings.any((n) => n.kind == NoticingKind.rhythm), isFalse);
    });

    test('says where time went this week', () {
      final result = phoneNoticings(_days(28), _now);

      final apps = result.noticings.firstWhere((n) => n.kind == NoticingKind.apps);
      // 90 of 140 minutes a day.
      expect(
        apps.text,
        'Most of your phone time this week was social, about 64% of it.',
      );
    });

    test('says nothing about apps without category totals', () {
      final rows = [
        for (final row in _days(28))
          DailyFeatures(
            dayKey: row.dayKey,
            sources: row.sources,
            screenOnMinutes: row.screenOnMinutes,
          ),
      ];

      expect(
        phoneNoticings(rows, _now).noticings.any((n) => n.kind == NoticingKind.apps),
        isFalse,
      );
    });
  });

  group('wording', () {
    test('describes and never judges, compares, or diagnoses', () {
      final text = phoneNoticings(_days(28), _now).noticings
          .map((n) => '${n.meta} ${n.text}')
          .join(' ')
          .toLowerCase();

      for (final word in [
        'too much',
        'too little',
        'enough',
        'healthy',
        'unhealthy',
        'goal',
        'target',
        'average',
        'most people',
        'better',
        'worse',
        'addict',
        'should',
        'sleep disorder',
        'insomnia',
        'depress',
      ]) {
        expect(text, isNot(contains(word)), reason: '"$word" would be a judgement');
      }
    });
  });
}
