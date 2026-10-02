// Dev-only spike for the usage-access work. Not part of the product.
//
// Reports structural facts about what Android will give the collector on this
// device: how far back events go, how many there are per day and type, and how
// well apps resolve to a category without the broad package-visibility
// permission. It prints counts only and never an app name or package.
//
// Run on a connected device:
//   flutter run -d <device> -t tool/usage_probe/main.dart
import 'package:flutter/material.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/domain/footprint/app_categories.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _service = MethodChannelUsageCollector();
  String _report = 'Running...';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final lines = <String>[];
    void log(String line) {
      lines.add(line);
      debugPrint('USAGE_PROBE $line');
    }

    final access = await _service.hasAccess();
    log('access=$access');
    if (!access) {
      setState(() => _report = lines.join('\n'));
      return;
    }

    final now = DateTime.now();
    // One day at a time, as the real collector will, newest first.
    final byDay = <String, Map<UsageEventType, int>>{};
    DateTime? earliest;
    final packages = <String>{};
    for (var back = 0; back < 21; back++) {
      final start = DateTime(now.year, now.month, now.day - back);
      final end = DateTime(now.year, now.month, now.day - back + 1);
      final events = await _service.events(from: start, to: end);
      if (events.isEmpty) continue;
      final counts = <UsageEventType, int>{};
      for (final event in events) {
        counts[event.type] = (counts[event.type] ?? 0) + 1;
        if (earliest == null || event.time.isBefore(earliest)) {
          earliest = event.time;
        }
      }
      packages.addAll(packagesIn(events));
      final key = '${start.year}-${start.month.toString().padLeft(2, '0')}-'
          '${start.day.toString().padLeft(2, '0')}';
      byDay[key] = counts;
    }

    log('daysWithEvents=${byDay.length} earliestEvent=$earliest');
    for (final entry in byDay.entries) {
      final c = entry.value;
      log(
        '${entry.key} screenOn=${c[UsageEventType.screenOn] ?? 0} '
        'screenOff=${c[UsageEventType.screenOff] ?? 0} '
        'unlock=${c[UsageEventType.keyguardHidden] ?? 0} '
        'fg=${c[UsageEventType.appForeground] ?? 0}',
      );
    }

    final described = await _service.describeApps(packages.toList());
    final visible = described.values.where((d) => d.visible).length;
    final withPlatformCategory = described.values
        .where((d) => d.category != null)
        .length;
    final ignored = described.values.where((d) => d.ignore).length;
    final resolve = categoryResolverFor(described);
    final tally = <String, int>{};
    for (final package in packages) {
      final category = resolve(package) ?? '(ignored)';
      tally[category] = (tally[category] ?? 0) + 1;
    }
    log('packages=${packages.length} visible=$visible '
        'withPlatformCategory=$withPlatformCategory ignored=$ignored');
    log('categoryTally=$tally');

    if (mounted) setState(() => _report = lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usage probe')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(_report),
      ),
    );
  }
}
