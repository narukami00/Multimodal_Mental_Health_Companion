import '../../core/models/user_profile.dart';
import '../capacity/capacity_estimator.dart';

/// The short, plain-words description of the person that may be sent to the
/// companion so replies can fit them.
///
/// It is built from an allowlist and never from raw data: no numbers, no scores
/// from questionnaires, no app names, no times, and no mention of *where* a
/// signal came from. Phone-derived signals shape it only through capacity, and
/// even then only as "may have limited energy", never as "you slept badly".
class ProfileSnippet {
  const ProfileSnippet({required this.lines});

  /// Bumped when the shape of the snippet changes, so a server can tell.
  static const version = 1;

  /// A generous cap, roughly 100 tokens.
  static const maxCharacters = 420;

  static const empty = ProfileSnippet(lines: []);

  final List<String> lines;

  bool get isEmpty => lines.isEmpty;

  /// Exactly what is sent, and what the person is shown.
  String get text => lines.join(' ');

  int get approxTokens => (text.length / 4).ceil();
}

/// Builds the snippet.
///
/// Returns an empty snippet when [consented] is false, so a missing consent can
/// never leak signals by being forgotten at a call site.
ProfileSnippet buildProfileSnippet({
  required bool consented,
  required UserProfile profile,
  Capacity? capacity,
  List<double> recentMoodScores = const [],
  List<String> recentThemes = const [],
}) {
  if (!consented) return ProfileSnippet.empty;
  final lines = <String>[];

  // How they like to be spoken to: their own choices, in plain words.
  final likes = <String>[
    for (final p in profile.interactionPreferences)
      if (_preference[p] != null) _preference[p]!,
    for (final c in profile.constraints)
      if (_constraint[c] != null) _constraint[c]!,
  ];
  if (likes.isNotEmpty) lines.add('Prefers ${_join(likes)}.');

  // Lately, from what they have said and chosen.
  final lately = <String>[];
  final mood = _moodWords(recentMoodScores);
  if (mood != null) lately.add(mood);
  final themes = [
    for (final t in recentThemes)
      if (_themeWords[t] != null) _themeWords[t]!,
  ];
  if (themes.isNotEmpty) lately.add('${_join(themes)} came up recently');
  if (lately.isNotEmpty) lines.add('Lately: ${_join(lately)}.');

  // Right now: only when the reading is firm enough to mean something.
  if (capacity != null && capacity.isLow && capacity.confidence >= 0.5) {
    lines.add('Right now: may have limited energy, keep it gentle.');
  }

  return _capped(lines);
}

ProfileSnippet _capped(List<String> lines) {
  // Drop whole lines from the end rather than cut a sentence in half.
  final kept = [...lines];
  while (kept.isNotEmpty && kept.join(' ').length > ProfileSnippet.maxCharacters) {
    kept.removeLast();
  }
  return ProfileSnippet(lines: kept);
}

String? _moodWords(List<double> scores) {
  if (scores.length < 3) return null;
  final last = scores.sublist(scores.length - 3);
  final recent = last.reduce((a, b) => a + b) / last.length;
  final overall = scores.reduce((a, b) => a + b) / scores.length;
  if (recent <= -0.4 || (recent < overall - 0.3 && recent < 0.1)) {
    return 'mood has felt lower than usual for a few days';
  }
  if (recent >= 0.6) return 'mood has felt brighter';
  return null;
}

const _preference = {
  'Gentle tone': 'a gentle tone',
  'Direct tone': 'a direct tone',
  'Quiet prompts': 'quiet, low-pressure prompts',
  'More context': 'a little more context',
};

const _constraint = {
  'Short moments': 'short moments',
  'Low energy options': 'low-energy ideas',
  'Quiet at home': 'quiet things at home',
  'Limited mobility': 'ideas that need little movement',
};

const _themeWords = {
  'work': 'work',
  'relationships': 'people close to them',
  'sleep': 'sleep',
  'health': 'health',
  'home': 'home',
  'money': 'money',
};

String _join(List<String> parts) {
  if (parts.length <= 1) return parts.join();
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}
