import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../core/theme/app_theme.dart';
import '../sessions/session_controller.dart';
import 'session_detail_page.dart';

class JournalPage extends StatelessWidget {
  const JournalPage({
    required this.sessionController,
    super.key,
  });

  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sessionController,
      builder: (context, _) {
        final sessions = sessionController.sessions;
        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 6),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Journal', style: Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 7),
                            Text(
                              'your days, gently kept',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    letterSpacing: 0.6,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showFilterNote(context),
                        tooltip: 'Filter entries',
                        icon: const Icon(Icons.tune_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.amber.withValues(alpha: 0.12),
                          foregroundColor: AppColors.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (sessions.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyJournal(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
                  sliver: SliverList.builder(
                    itemCount: _groupSessions(sessions).length,
                    itemBuilder: (context, index) {
                      final group = _groupSessions(sessions)[index];
                      return _JournalDayGroup(
                        date: group.date,
                        sessions: group.sessions,
                        onOpen: (session) => _openSession(context, session),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openSession(BuildContext context, SessionRecord session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailPage(session: session),
      ),
    );
  }

  void _showFilterNote(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Filters will arrive as more ways to check in become available.')),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(19),
                    child: Icon(Icons.auto_stories_outlined, size: 34, color: AppColors.deepAmber),
                  ),
                ),
                const SizedBox(height: 18),
                Text('A blank page is a beginning.', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Your check-ins and reflections will gather here, one moment at a time.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JournalDayGroup extends StatelessWidget {
  const _JournalDayGroup({
    required this.date,
    required this.sessions,
    required this.onOpen,
  });

  final DateTime date;
  final List<SessionRecord> sessions;
  final ValueChanged<SessionRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateLabel(context, date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TimelineDot(size: 11),
              const SizedBox(width: 10),
              Text(dateLabel, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 9),
              Text(
                '${date.month}/${date.day}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < sessions.length; index++) ...[
            _JournalEntryCard(session: sessions[index], onTap: () => onOpen(sessions[index])),
            if (index < sessions.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  String _dateLabel(BuildContext context, DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(value.year, value.month, value.day);
    if (dateOnly == today) return 'Today';
    if (dateOnly == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return MaterialLocalizations.of(context).formatFullDate(value);
  }
}

class _JournalEntryCard extends StatelessWidget {
  const _JournalEntryCard({
    required this.session,
    required this.onTap,
  });

  final SessionRecord session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isVideo = session.mode == CaptureMode.video;
    final accent = isVideo ? AppColors.coral : AppColors.amber;
    final modeLabel = switch (session.mode) {
      CaptureMode.text => 'Journal note',
      CaptureMode.voice => 'Voice check-in',
      CaptureMode.video => 'Video check-in',
    };
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(session.createdAt),
    );
    final snippet = session.text?.trim().isNotEmpty == true
        ? session.text!.trim()
        : session.mood != null
            ? 'You felt ${session.mood}.'
            : 'A $modeLabel, gently kept.';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MoodMarker(accent: accent, icon: _modeIcon(session.mode)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            modeLabel.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.mutedInk,
                                  letterSpacing: 1.0,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Text(time, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35),
                    ),
                    if (session.mood != null) ...[
                      const SizedBox(height: 9),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          child: Text(
                            session.mood!,
                            style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 7, top: 28),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.mutedInk),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _modeIcon(CaptureMode mode) {
    return switch (mode) {
      CaptureMode.text => Icons.edit_outlined,
      CaptureMode.voice => Icons.graphic_eq_rounded,
      CaptureMode.video => Icons.videocam_outlined,
    };
  }
}

class _MoodMarker extends StatelessWidget {
  const _MoodMarker({required this.accent, required this.icon});

  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, size: 21, color: accent),
      ),
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.amber,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SessionDayGroup {
  const _SessionDayGroup({required this.date, required this.sessions});

  final DateTime date;
  final List<SessionRecord> sessions;
}

List<_SessionDayGroup> _groupSessions(List<SessionRecord> sessions) {
  final groups = <String, List<SessionRecord>>{};
  final dates = <String, DateTime>{};
  for (final session in sessions) {
    final date = DateTime(session.createdAt.year, session.createdAt.month, session.createdAt.day);
    final key = date.toIso8601String();
    groups.putIfAbsent(key, () => []).add(session);
    dates[key] = date;
  }

  final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final key in keys)
      _SessionDayGroup(date: dates[key]!, sessions: List.unmodifiable(groups[key]!)),
  ];
}
