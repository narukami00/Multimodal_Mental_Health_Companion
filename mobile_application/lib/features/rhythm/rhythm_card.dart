import 'package:flutter/material.dart';

import '../../domain/rhythm/rhythm_summary.dart';
import '../profile/profile_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'rhythm_detail_page.dart';

/// Human-readable counts with correct pluralisation, e.g.
/// `2 check-ins · 1 rest day`.
String rhythmCountsLabel(RhythmSummary summary) {
  final checkIns = summary.checkInCount == 1 ? 'check-in' : 'check-ins';
  final rests = summary.restCount == 1 ? 'rest day' : 'rest days';
  return '${summary.checkInCount} $checkIns · ${summary.restCount} $rests';
}

/// Compact rhythm summary for the home screen.
///
/// Shows what actually happened, never a target: no consecutive-day count, no
/// fraction of a goal, and a blank day is neutral rather than a miss.
class RhythmCard extends StatelessWidget {
  const RhythmCard({
    required this.sessionController,
    required this.profileController,
    required this.suggestionController,
    super.key,
  });

  final SessionController sessionController;
  final ProfileController profileController;
  final SuggestionController suggestionController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        sessionController,
        profileController,
        suggestionController,
      ]),
      builder: (context, _) {
        final summary = summariseRhythm(
          sessions: sessionController.sessions,
          restDays: profileController.restDays,
          suggestions: suggestionController.history,
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF7F2E6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14785C28),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RhythmDetailPage(
                    sessionController: sessionController,
                    profileController: profileController,
                    suggestionController: suggestionController,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3DC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.eco_rounded,
                        size: 20,
                        color: Color(0xFFB57A12),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.isEmpty
                                ? 'YOUR RHYTHM'
                                : 'LAST 4 WEEKS',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                              color: Color(0xFFBCAC8E),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            summary.isEmpty
                                ? 'Your rhythm'
                                : rhythmCountsLabel(summary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4A4133),
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            summary.isEmpty
                                ? 'Appears here after a few check-ins.'
                                : 'Resting counts as showing up.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF93887A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _WeekStrip(days: summary.recentWeek),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The most recent seven days, as a small neutral strip.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});

  final List<RhythmDay> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < days.length; index++) ...[
          if (index > 0) const SizedBox(width: 4),
          RhythmDot(day: days[index], size: days[index].isToday ? 10 : 8),
        ],
      ],
    );
  }
}

/// A single day mark: filled for a check-in, a soft ring for rest, and a faint
/// dot when the user only answered a suggestion. Blank days stay neutral.
class RhythmDot extends StatelessWidget {
  const RhythmDot({required this.day, this.size = 10, super.key});

  final RhythmDay day;
  final double size;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFB534);
    const neutral = Color(0xFFEFE6D2);
    const today = Color(0xFFFF7F50);

    if (day.isRestDay && !day.hasCheckIn) {
      return Container(
        key: ValueKey('dot-rest-${day.date.toIso8601String()}'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: day.isToday ? today : amber,
            width: 1.6,
          ),
        ),
      );
    }

    final Color fill;
    if (day.hasCheckIn) {
      fill = day.isToday ? today : amber;
    } else if (day.hasSuggestionOutcome) {
      fill = const Color(0x66FFB534);
    } else {
      fill = neutral;
    }

    return Container(
      key: ValueKey('dot-${day.date.toIso8601String()}'),
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    );
  }
}

/// Shared legend so the marks are never a guess.
class RhythmLegend extends StatelessWidget {
  const RhythmLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Color(0xFF93887A),
    );

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFFFFB534),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text('check-in', style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFB534), width: 1.6),
              ),
            ),
            const SizedBox(width: 6),
            const Text('rest day', style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFFEFE6D2),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text('nothing logged', style: style),
          ],
        ),
      ],
    );
  }
}
