import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/activity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_back_button.dart';
import '../../data/repositories/asset_activity_library_repository.dart';
import '../../domain/library/activity_stats.dart';
import '../art/activity_art.dart';
import '../insights/mood_tab.dart' show moodColors;
import '../suggestions/suggestion_controller.dart';

String _kind(ActivityType type) => switch (type) {
      ActivityType.movement => 'Move',
      ActivityType.social => 'Connect',
      ActivityType.creative => 'Create',
      ActivityType.nature => 'Outside',
      ActivityType.mindfulness => 'Pause',
      ActivityType.learning => 'Learn',
      ActivityType.productivity => 'Small task',
    };

String _effort(ActivityEffort e) => switch (e) {
      ActivityEffort.low => 'Gentle',
      ActivityEffort.medium => 'Some effort',
      ActivityEffort.high => 'More effort',
    };

String _ago(DateTime at, DateTime now) {
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  return '${days ~/ 30} months ago';
}

/// The reviewed starter ideas as a gallery: a row of kinds to filter by, then each idea by name with
/// whether (and how often) you have tried it. Tapping one opens its painted scene and what you told
/// the app about it: how many times, how it was rated, how you said you felt afterwards.
class ActivityLibraryPage extends StatefulWidget {
  const ActivityLibraryPage({this.suggestionController, super.key});

  final SuggestionController? suggestionController;

  @override
  State<ActivityLibraryPage> createState() => _ActivityLibraryPageState();
}

class _ActivityLibraryPageState extends State<ActivityLibraryPage> {
  late final Future<List<Activity>> _activities;
  ActivityType? _filter;
  String? _open;

  @override
  void initState() {
    super.initState();
    _activities = AssetActivityLibraryRepository().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFCE8),
      appBar: AppBar(
        leading: const PageBackButton(),
        title: const Text('Activity library'),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<List<Activity>>(
        future: _activities,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This library is unavailable until every entry passes review.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final controller = widget.suggestionController;
          return ListenableBuilder(
            listenable: controller ?? ValueNotifier<int>(0),
            builder: (context, _) {
              final all = snapshot.data!;
              final stats = ActivityStats.byActivity(controller?.history ?? const []);
              final shown = [for (final a in all) if (_filter == null || a.type == _filter) a];
              final now = DateTime.now();
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: shown.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _Header(
                          all: all,
                          stats: stats,
                          filter: _filter,
                          onFilter: (t) => setState(() {
                            _filter = t;
                            _open = null;
                          }),
                        );
                      }
                      final activity = shown[i - 1];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _IdeaTile(
                          key: ValueKey('idea-${activity.id}'),
                          activity: activity,
                          stats: stats[activity.id] ?? ActivityStats.empty,
                          open: _open == activity.id,
                          now: now,
                          onTap: () => setState(() => _open = _open == activity.id ? null : activity.id),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.all, required this.stats, required this.filter, required this.onFilter});

  final List<Activity> all;
  final Map<String, ActivityStats> stats;
  final ActivityType? filter;
  final ValueChanged<ActivityType?> onFilter;

  @override
  Widget build(BuildContext context) {
    final tried = all.where((a) => (stats[a.id]?.done ?? 0) > 0).length;
    final lighter = stats.values.fold<int>(0, (n, s) => n + s.lighter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('library-summary'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFE3B0), Color(0xFFFFD0B5)],
            ),
          ),
          child: Row(
            children: [
              _Stat(value: '${all.length}', label: 'ideas'),
              _Stat(value: '$tried', label: 'you have tried'),
              _Stat(value: '$lighter', label: 'times you felt lighter'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _KindChip(label: 'All', selected: filter == null, onTap: () => onFilter(null), child: const Icon(Icons.apps_rounded, color: Color(0xFF8A5A1E))),
              for (final type in ActivityType.values)
                _KindChip(
                  label: _kind(type),
                  selected: filter == type,
                  onTap: () => onFilter(filter == type ? null : type),
                  child: ActivityArt(type: type, animate: false, progress: 0.3, circle: true),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Lifestyle ideas, not treatment. Each one was reviewed before it could be offered.',
          style: TextStyle(fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.mutedInk),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF5B3A12))),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF8A5A1E))),
          ],
        ),
      );
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.selected, required this.onTap, required this.child});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('kind-$label'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? const Color(0xFFFFB534) : const Color(0x14000000),
              ),
              child: ClipOval(child: Center(child: SizedBox(width: 52, height: 52, child: child))),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: const Color(0xFF5C4C36)),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile({required this.activity, required this.stats, required this.open, required this.now, required this.onTap, super.key});

  final Activity activity;
  final ActivityStats stats;
  final bool open;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ActivityArt.paletteFor(activity.type);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: open ? palette.a.withValues(alpha: 0.5) : const Color(0x1A000000)),
        boxShadow: [BoxShadow(color: palette.ink.withValues(alpha: open ? 0.18 : 0.07), blurRadius: open ? 22 : 10, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (open)
                  SizedBox(
                    key: const ValueKey('idea-art'),
                    height: 170,
                    width: double.infinity,
                    child: ActivityArt(type: activity.type),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (!open)
                        SizedBox(
                          width: 54,
                          height: 54,
                          child: ActivityArt(type: activity.type, animate: false, progress: 0.3, circle: true),
                        ),
                      if (!open) const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activity.title, style: const TextStyle(fontSize: 15.5, height: 1.2, fontWeight: FontWeight.w800, color: Color(0xFF2E2418))),
                            const SizedBox(height: 3),
                            Text(
                              '${_kind(activity.type)} · ${activity.durationMinutes} min · ${_effort(activity.effort)}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.ink),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Badge(stats: stats, ink: palette.ink),
                    ],
                  ),
                ),
                if (open) _Details(activity: activity, stats: stats, now: now, palette: palette),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.stats, required this.ink});

  final ActivityStats stats;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final tried = stats.tried;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tried ? ink.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        border: tried ? null : Border.all(color: const Color(0x26000000)),
      ),
      child: Text(
        tried ? 'Tried ${stats.done}×' : 'New',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tried ? ink : AppColors.mutedInk),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.activity, required this.stats, required this.now, required this.palette});

  final Activity activity;
  final ActivityStats stats;
  final DateTime now;
  final ArtPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('idea-details'),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(activity.description, style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF5C4C36), fontWeight: FontWeight.w500)),
          const SizedBox(height: 14),
          if (!stats.tried && stats.offered == 0)
            const Text(
              'You have not been offered this one yet.',
              key: ValueKey('idea-untried'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.mutedInk),
            )
          else ...[
            Row(
              children: [
                _Num(value: '${stats.offered}', label: 'offered', color: palette),
                _Num(value: '${stats.done}', label: 'done', color: palette),
                _Num(value: '${stats.skipped}', label: 'skipped', color: palette),
              ],
            ),
            if (stats.lastDone != null) ...[
              const SizedBox(height: 10),
              Text('Last done ${_ago(stats.lastDone!, now)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.mutedInk)),
            ],
            if (stats.averageRating != null) ...[
              const SizedBox(height: 10),
              Row(
                key: const ValueKey('idea-rating'),
                children: [
                  for (var s = 1; s <= 5; s++)
                    Icon(
                      s <= stats.averageRating!.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 20,
                      color: const Color(0xFFFFB534),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    stats.ratedCount == 1 ? 'your rating' : 'your average of ${stats.ratedCount}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.mutedInk),
                  ),
                ],
              ),
            ],
            if (stats.compared > 0) ...[
              const SizedBox(height: 14),
              Container(
                key: const ValueKey('idea-felt'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: palette.skyTop.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How you said you felt after', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: palette.ink)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        children: [
                          if (stats.lighter > 0) Expanded(flex: stats.lighter, child: Container(height: 10, color: const Color(0xFFFFB534))),
                          if (stats.same > 0) Expanded(flex: stats.same, child: Container(height: 10, color: const Color(0xFFD9CBB0))),
                          if (stats.heavier > 0) Expanded(flex: stats.heavier, child: Container(height: 10, color: const Color(0xFFB4ADD6))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (stats.lighter > 0) 'Lighter ${stats.lighter}',
                        if (stats.same > 0) 'About the same ${stats.same}',
                        if (stats.heavier > 0) 'Heavier ${stats.heavier}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5C4C36)),
                    ),
                  ],
                ),
              ),
            ],
            if (stats.feltAfter.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final e in stats.feltAfter.entries)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: moodColors[e.key], shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text('${Moods.display(e.key)} ${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5C4C36))),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final ArtPalette color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color.ink)),
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.mutedInk)),
          ],
        ),
      );
}
