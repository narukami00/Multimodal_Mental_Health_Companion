import '../../core/constants/moods.dart';
import '../../core/models/break_annotation.dart';
import '../../core/models/chat_conversation_record.dart';
import '../../core/models/emotion_result.dart';
import '../../core/models/session_record.dart';
import '../../core/models/suggestion_record.dart';
import '../chat/conversation_breakdown.dart';

/// Empirical user correction tendency for one predicted emotion bucket.
///
/// Computed strictly from user-reviewed journal readings without mutating raw
/// [EmotionResult] outputs. Activated only once enough reviews exist so small
/// samples never trigger spurious hints.
class MoodCalibrationRule {
  const MoodCalibrationRule({
    required this.predictedBucket,
    required this.preferredMood,
    required this.correctedCount,
    required this.totalForBucket,
  });

  final String predictedBucket;

  /// Target canonical mood key in [Moods.values] (e.g. 'Steady', 'Wobbly').
  final String preferredMood;
  final int correctedCount;
  final int totalForBucket;

  double get agreementShare =>
      totalForBucket == 0 ? 0 : correctedCount / totalForBucket;
}

/// Lightweight record of a gentle "is everything alright?" check-in.
class LifePulseSignal {
  const LifePulseSignal({
    required this.moodTag,
    required this.at,
    this.note,
  });

  final String moodTag;
  final DateTime at;
  final String? note;
}

/// On-device personalization profile derived from user reviews, shift feedback,
/// helpful activities, and life check-ins.
class PersonalPatternProfile {
  const PersonalPatternProfile({
    required this.totalReviewedMoods,
    required this.acceptedMoods,
    required this.correctedMoods,
    required this.rulesByBucket,
    required this.correctionRankByBucket,
    required this.recurringShiftContexts,
    required this.helpfulTags,
    this.latestPulse,
  });

  static const int minReviewsForCalibration = 5;
  static const int minBucketSamples = 3;

  final int totalReviewedMoods;
  final int acceptedMoods;
  final int correctedMoods;
  final Map<String, MoodCalibrationRule> rulesByBucket;
  final Map<String, List<String>> correctionRankByBucket;
  final List<({String context, int count})> recurringShiftContexts;
  final List<String> helpfulTags;
  final LifePulseSignal? latestPulse;

  bool get isCalibrated => totalReviewedMoods >= minReviewsForCalibration;

  static String bucketForReading(EmotionResult reading) {
    final mapped = Moods.fromReadingMood(reading.mood);
    if (mapped != null) return mapped.toLowerCase();
    final raw = (reading.mood ?? '').trim().toLowerCase();
    return raw.isEmpty ? 'unsure' : raw;
  }

  /// Returns an active personal pattern hint for [reading], or null when not calibrated
  /// or no clear pattern applies.
  MoodCalibrationRule? calibrationFor(EmotionResult reading) {
    if (!isCalibrated) return null;
    final bucket = bucketForReading(reading);
    final rule = rulesByBucket[bucket];
    if (rule == null) return null;
    final currentCanonical = Moods.fromReadingMood(reading.mood);
    if (currentCanonical == rule.preferredMood) return null;
    return rule;
  }

  /// Returns [Moods.values] ordered by the user's empirical correction counts
  /// for [reading]'s predicted bucket, preserving canonical order for ties.
  List<String> rankedMoodChoices(EmotionResult reading) {
    final bucket = bucketForReading(reading);
    return correctionRankByBucket[bucket] ?? Moods.values;
  }

  /// Builds safe, concise, non-clinical personalization phrases suitable for
  /// showing transparently to the user and (if consented) including in the
  /// companion LLM memory snippet.
  List<String> safePersonalizationPhrases({DateTime? now}) {
    final clockNow = now ?? DateTime.now();
    final lines = <String>[];

    if (latestPulse != null &&
        clockNow.difference(latestPulse!.at) <= const Duration(hours: 48)) {
      final pulsePhrase = _pulsePhrase(latestPulse!);
      if (pulsePhrase != null) lines.add(pulsePhrase);
    }

    final topContexts = [
      for (final item in recurringShiftContexts)
        if (item.count >= 2) item.context.toLowerCase(),
    ];
    if (topContexts.isNotEmpty) {
      lines.add(
        '${_joinWords(topContexts.take(2).toList())} came up around emotional shifts',
      );
    }

    if (helpfulTags.isNotEmpty) {
      lines.add('often finds ${_joinWords(helpfulTags.take(2).toList())} helpful');
    }

    return lines;
  }

  factory PersonalPatternProfile.from({
    required List<SessionRecord> sessions,
    List<ChatConversationRecord> conversations = const [],
    List<BreakAnnotation> breakAnnotations = const [],
    List<SuggestionRecord> suggestions = const [],
    LifePulseSignal? latestPulse,
  }) {
    var totalReviewed = 0;
    var accepted = 0;
    var corrected = 0;

    final bucketTotals = <String, int>{};
    final bucketTargets = <String, Map<String, int>>{};

    for (final session in sessions) {
      final reading = session.reading;
      final review = session.moodReview;
      if (reading == null || review == null) continue;
      if (review.status == MoodReviewStatus.skipped) continue;

      totalReviewed++;
      final bucket = bucketForReading(reading);
      bucketTotals[bucket] = (bucketTotals[bucket] ?? 0) + 1;

      if (review.status == MoodReviewStatus.accepted) {
        accepted++;
      } else if (review.status == MoodReviewStatus.corrected) {
        corrected++;
        final target = Moods.normalize(review.mood);
        if (target != null) {
          final map = bucketTargets.putIfAbsent(bucket, () => {});
          map[target] = (map[target] ?? 0) + 1;
        }
      }
    }

    final rules = <String, MoodCalibrationRule>{};
    final ranks = <String, List<String>>{};

    for (final entry in bucketTotals.entries) {
      final bucket = entry.key;
      final total = entry.value;
      final targets = bucketTargets[bucket] ?? const {};

      final sortedChoices = List<String>.of(Moods.values)
        ..sort((a, b) {
          final ca = targets[a] ?? 0;
          final cb = targets[b] ?? 0;
          if (ca != cb) return cb.compareTo(ca);
          return Moods.values.indexOf(a).compareTo(Moods.values.indexOf(b));
        });
      ranks[bucket] = List.unmodifiable(sortedChoices);

      if (totalReviewed >= minReviewsForCalibration &&
          total >= minBucketSamples &&
          targets.isNotEmpty) {
        String? topMood;
        var topCount = 0;
        for (final t in targets.entries) {
          if (t.value > topCount) {
            topCount = t.value;
            topMood = t.key;
          }
        }
        if (topMood != null &&
            topCount >= minBucketSamples &&
            topCount * 2 > total) {
          rules[bucket] = MoodCalibrationRule(
            predictedBucket: bucket,
            preferredMood: topMood,
            correctedCount: topCount,
            totalForBucket: total,
          );
        }
      }
    }

    final shiftContextCounts = <String, int>{};
    for (final conv in conversations) {
      for (final review in conv.shiftReviews) {
        if (review.shiftFit == ShiftAgreement.disagrees ||
            review.shiftFit == ShiftAgreement.skipped) {
          continue;
        }
        final ctx = review.proposedContext?.trim();
        if (ctx != null &&
            ctx.isNotEmpty &&
            review.reasonFit == ShiftAgreement.agrees) {
          shiftContextCounts[ctx] = (shiftContextCounts[ctx] ?? 0) + 1;
        }
      }
      // Also incorporate shift contexts inferred only if already confirmed above.
    }
    for (final ann in breakAnnotations) {
      if (ann.status == BreakAnnotationStatus.answered &&
          ann.theme != null &&
          ann.theme!.trim().isNotEmpty) {
        final label = _themeToDisplay(ann.theme!.trim());
        shiftContextCounts[label] = (shiftContextCounts[label] ?? 0) + 1;
      }
    }

    final recurring = [
      for (final e in shiftContextCounts.entries)
        (context: e.key, count: e.value),
    ]..sort((a, b) => b.count.compareTo(a.count));

    final helpfulTagCounts = <String, int>{};
    for (final rec in suggestions) {
      if (rec.useful != SuggestionUsefulness.up) continue;
      for (final rawTag in rec.contextTags) {
        final clean = rawTag.trim().toLowerCase();
        if (clean.isEmpty) continue;
        helpfulTagCounts[clean] = (helpfulTagCounts[clean] ?? 0) + 1;
      }
    }
    final helpfulEntries = helpfulTagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final helpfulTags = {
      for (final e in helpfulEntries)
        if (_safeHelpfulTag[e.key] != null) _safeHelpfulTag[e.key]!,
    }.toList();

    return PersonalPatternProfile(
      totalReviewedMoods: totalReviewed,
      acceptedMoods: accepted,
      correctedMoods: corrected,
      rulesByBucket: Map.unmodifiable(rules),
      correctionRankByBucket: Map.unmodifiable(ranks),
      recurringShiftContexts: List.unmodifiable(recurring),
      helpfulTags: List.unmodifiable(helpfulTags),
      latestPulse: latestPulse,
    );
  }

  static String? _pulsePhrase(LifePulseSignal signal) {
    final note = _sanitizeShortNote(signal.note);
    final moodPart = switch (signal.moodTag) {
      'all_good' => 'doing okay lately',
      'stressed' => 'feeling busy or under pressure',
      'low' => 'carrying something a bit heavy',
      'tired' => 'feeling stretched or low on rest',
      'work' => 'focused on work or studies',
      'relationships' => 'thinking about people close to them',
      'sleep' => 'noticing sleep feeling off',
      'custom' => null,
      _ => null,
    };
    if (moodPart != null && note != null) {
      return 'checked in recently: $moodPart ("$note")';
    }
    if (note != null) {
      return 'shared what is on their mind: "$note"';
    }
    if (moodPart != null) {
      return 'checked in recently: $moodPart';
    }
    return null;
  }

  static String? _sanitizeShortNote(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return null;
    return clean.length <= 72 ? clean : '${clean.substring(0, 71).trimRight()}…';
  }

  static String _themeToDisplay(String theme) => switch (theme) {
    'work' => 'Work or study',
    'relationships' => 'People close to you',
    'sleep' => 'Sleep',
    'health' => 'Health',
    'home' => 'Home',
    'money' => 'Money',
    _ => theme[0].toUpperCase() + theme.substring(1),
  };

  static const _safeHelpfulTag = <String, String>{
    'breathe': 'breathing exercises',
    'breathing': 'breathing exercises',
    'ground': 'grounding exercises',
    'grounding': 'grounding exercises',
    'walk': 'short walks',
    'movement': 'gentle movement',
    'journal': 'writing things out',
    'reflect': 'quiet reflection',
    'rest': 'rest',
    'sleep': 'wind-down routines',
    'calm': 'calming resets',
    'connect': 'connecting with someone',
    'social': 'talking with people',
  };

  static String _joinWords(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }
}

/// Default welcome starter chips shown when no personalized signals apply.
const List<String> defaultChatStarters = [
  "I'm feeling a bit restless",
  'Help me unwind tonight',
  'Just want to vent',
  'Reflect on my day',
];

/// Returns a gentle, non-clinical starter prompt tailored to a recent
/// [LifePulseSignal], or null if no specific starter applies.
String? starterForLifePulse(LifePulseSignal signal) {
  final note = PersonalPatternProfile._sanitizeShortNote(signal.note);
  if (note != null) {
    final short =
        note.length <= 36 ? note : '${note.substring(0, 35).trimRight()}…';
    return 'Talk about "$short"';
  }
  return switch (signal.moodTag) {
    'stressed' => "Let's unpack what's making things busy",
    'tired' => 'Help me wind down — I feel tired',
    'low' => 'Things feel a bit heavy right now',
    'relationships' => 'Talk through what is happening with people',
    'sleep' => 'Help me reset my sleep tonight',
    'work' => 'Talk through work or study stress',
    'all_good' => 'Check in on what is going well',
    _ => null,
  };
}

/// Builds up to 4 deduplicated chat welcome starter chips from on-device
/// personalization signals, filling remaining slots from [fallback].
List<String> personalChatStarters({
  PersonalPatternProfile? profile,
  List<String> fallback = defaultChatStarters,
  DateTime? now,
}) {
  final clockNow = now ?? DateTime.now();
  final starters = <String>[];

  void addStarter(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final lower = clean.toLowerCase();
    if (starters.any((s) => s.toLowerCase() == lower)) return;
    starters.add(clean);
  }

  final pulse = profile?.latestPulse;
  if (pulse != null &&
      clockNow.difference(pulse.at) <= const Duration(hours: 48)) {
    final pulseStarter = starterForLifePulse(pulse);
    if (pulseStarter != null) addStarter(pulseStarter);
  }

  if (profile != null) {
    for (final ctx in profile.recurringShiftContexts) {
      if (ctx.count < 2) continue;
      final cleanCtx = ctx.context.trim();
      if (cleanCtx.isNotEmpty) {
        addStarter(
          "Let's unpack what's been happening with ${cleanCtx.toLowerCase()}",
        );
        break;
      }
    }
    for (final tag in profile.helpfulTags) {
      final cleanTag = tag.trim();
      if (cleanTag.isNotEmpty) {
        addStarter('Try $cleanTag together');
        break;
      }
    }
  }

  for (final item in fallback) {
    if (starters.length >= 4) break;
    addStarter(item);
  }
  return starters.take(4).toList(growable: false);
}

/// Keeps linter happy on unused imports when referenced dynamically.
typedef UnusedBreakdownRef = ConversationBreakdown;
