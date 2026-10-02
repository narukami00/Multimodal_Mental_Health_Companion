import 'dart:async';

import 'package:flutter/widgets.dart';

import 'phone_patterns_controller.dart';
import 'usage_recorder.dart';

/// Decides *when* to catch up on device usage: when the app starts, when it
/// returns to the foreground, and the moment phone patterns is switched on (so
/// the days Android still remembers are filled in straight away).
///
/// There is deliberately no background job. Usage is read after the fact and
/// Android keeps about ten days, so opening the app within a week loses
/// nothing, and a background task would have to survive each maker's battery
/// rules and run without the native channel. It also means that nothing reads
/// the phone while Solace is closed.
class UsageCollectionRunner with WidgetsBindingObserver {
  UsageCollectionRunner({
    required PhonePatternsController patterns,
    required UsageRecorder recorder,
  }) : _patterns = patterns,
       _recorder = recorder;

  final PhonePatternsController _patterns;
  final UsageRecorder _recorder;

  bool _running = false;
  bool _runAgain = false;
  bool _wasCollecting = false;

  /// Starts listening for the moments worth catching up on.
  void start() {
    _wasCollecting = _patterns.isCollecting;
    WidgetsBinding.instance.addObserver(this);
    _patterns.addListener(_onPatternsChanged);
  }

  /// Re-checks Android's access, then catches up if collecting. Calls that
  /// arrive while a run is in progress are folded into one more run afterwards,
  /// so two triggers never read at the same time.
  Future<void> run() async {
    if (_running) {
      _runAgain = true;
      return;
    }
    _running = true;
    try {
      await _patterns.refresh();
      if (_patterns.isCollecting) {
        final written = await _recorder.catchUp();
        // Any open page is told, so it shows the days as they land.
        if (written > 0) _patterns.dataChanged();
      }
    } catch (error) {
      // Collection is best effort: a failure must never reach the person.
      debugPrint('UsageCollectionRunner warning: $error');
    } finally {
      _running = false;
    }
    if (_runAgain) {
      _runAgain = false;
      await run();
    }
  }

  void _onPatternsChanged() {
    final collecting = _patterns.isCollecting;
    final justStarted = collecting && !_wasCollecting;
    _wasCollecting = collecting;
    if (justStarted) unawaited(run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(run());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _patterns.removeListener(_onPatternsChanged);
  }
}
