import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/models/app_description.dart';
import '../core/models/usage_event.dart';

/// Reads device usage, as the platform allows it.
///
/// An interface so everything above it can be tested with a fake, and so the
/// platform channel stays one small, replaceable piece.
abstract interface class UsageCollectorService {
  /// Whether the user has granted usage access.
  Future<bool> hasAccess();

  /// Opens the system screen where it is granted. False if it could not open.
  Future<bool> openAccessSettings();

  /// Events in [from, to). Empty without access, or on a platform failure.
  Future<List<UsageEvent>> events({
    required DateTime from,
    required DateTime to,
  });

  /// What each package is. Packages the platform will not describe are omitted.
  Future<Map<String, AppDescription>> describeApps(List<String> packages);
}

class MethodChannelUsageCollector implements UsageCollectorService {
  MethodChannelUsageCollector({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel(
    'com.sysmentalhealth.solace_mobile/usage_collector',
  );

  static final MethodChannelUsageCollector instance =
      MethodChannelUsageCollector();

  final MethodChannel _channel;

  @override
  Future<bool> hasAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } catch (error) {
      debugPrint('UsageCollector access warning: $error');
      return false;
    }
  }

  @override
  Future<bool> openAccessSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAccessSettings') ?? false;
    } catch (error) {
      debugPrint('UsageCollector settings warning: $error');
      return false;
    }
  }

  @override
  Future<List<UsageEvent>> events({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('events', {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      });
      return [
        for (final entry in raw ?? const <Object?>[])
          if (UsageEvent.fromMap(entry) case final event?) event,
      ];
    } catch (error) {
      debugPrint('UsageCollector events warning: $error');
      return const [];
    }
  }

  @override
  Future<Map<String, AppDescription>> describeApps(
    List<String> packages,
  ) async {
    if (packages.isEmpty) return const {};
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'describeApps',
        {'packages': packages},
      );
      return {
        for (final entry in (raw ?? const <String, Object?>{}).entries)
          if (AppDescription.fromMap(entry.value) case final description?)
            entry.key: description,
      };
    } catch (error) {
      debugPrint('UsageCollector describe warning: $error');
      return const {};
    }
  }
}
