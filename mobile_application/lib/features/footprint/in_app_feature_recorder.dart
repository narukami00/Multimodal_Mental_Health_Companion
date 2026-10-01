import 'dart:async';

import '../../core/models/chat_conversation_record.dart';
import '../../core/models/daily_features.dart';
import '../../core/models/session_record.dart';
import '../../core/models/user_profile.dart';
import '../../data/contracts/daily_features_repository.dart';
import '../../domain/footprint/in_app_features.dart';

/// Keeps the in-app part of each day's [DailyFeatures] row up to date.
///
/// It only reads what the app already holds (check-ins, chats, the profile) and
/// writes derived numbers, so it needs no consent beyond what saving those
/// things already has. Rows from other sources for the same day are merged, not
/// replaced.
///
/// Reads come through callbacks rather than controllers, so this depends on
/// nothing Flutter and a test can hand it plain lists.
class InAppFeatureRecorder {
  InAppFeatureRecorder({
    required DailyFeaturesRepository repository,
    required List<SessionRecord> Function() sessions,
    required List<ChatConversationRecord> Function() conversations,
    required UserProfile Function() profile,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 2),
  }) : _repository = repository,
       _sessions = sessions,
       _conversations = conversations,
       _profile = profile,
       _clock = clock ?? DateTime.now;

  final DailyFeaturesRepository _repository;
  final List<SessionRecord> Function() _sessions;
  final List<ChatConversationRecord> Function() _conversations;
  final UserProfile Function() _profile;
  final DateTime Function() _clock;

  /// How long to wait for activity to settle before rewriting today's row. Chat
  /// notifies on every message, and a row only needs to be right eventually.
  final Duration debounce;

  Timer? _timer;

  /// Rebuilds the row for [day] from what the app holds right now.
  Future<void> recordDay(DateTime day) async {
    final profile = _profile();
    final row = deriveInAppFeatures(
      day: day,
      sessions: _sessions(),
      conversations: _conversations(),
      firstRunAt: profile.firstRunAt,
      reminderMinutes: profile.reminderEnabled ? profile.reminderMinutes : null,
    );
    if (row != null) await _repository.upsert(row);
  }

  /// Rebuilds today and the days before it, to catch anything that changed
  /// while the app was closed or a day rolled over.
  Future<void> recordRecent({int days = 3}) async {
    final today = _clock();
    for (var back = 0; back < days; back++) {
      await recordDay(DateTime(today.year, today.month, today.day - back));
    }
  }

  /// Drops rows older than the retention the user has chosen. Returns how many.
  Future<int> prune() {
    final cutoff = retentionCutoffDayKey(
      _clock(),
      _profile().featureRetentionDays,
    );
    return _repository.deleteBefore(cutoff);
  }

  /// Asks for today's row to be rebuilt once activity has settled. Safe to call
  /// on every change notification.
  void scheduleToday() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(recordDay(_clock())));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
