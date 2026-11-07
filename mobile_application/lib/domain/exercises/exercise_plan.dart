import '../../core/models/activity.dart';

/// The guided exercises, as plain data and one pure timing function, so the screens only have to draw them.

enum BreathPhase { inhale, holdIn, exhale, holdOut }

/// A breathing rhythm in whole seconds. A phase of zero seconds is skipped.
class BreathPattern {
  const BreathPattern({
    required this.inSeconds,
    required this.outSeconds,
    required this.cycles,
    this.holdInSeconds = 0,
    this.holdOutSeconds = 0,
  });

  final int inSeconds;
  final int holdInSeconds;
  final int outSeconds;
  final int holdOutSeconds;
  final int cycles;

  int get cycleSeconds => inSeconds + holdInSeconds + outSeconds + holdOutSeconds;
  Duration get total => Duration(seconds: cycleSeconds * cycles);
}

/// Where a breathing exercise is at one moment.
class BreathMoment {
  const BreathMoment({
    required this.phase,
    required this.phaseProgress,
    required this.cycle,
    required this.size,
    required this.done,
  });

  final BreathPhase phase;

  /// 0 to 1 through the current phase.
  final double phaseProgress;

  /// Zero-based number of the cycle in progress.
  final int cycle;

  /// How full the lungs are, 0 (empty) to 1 (full): what the orb shows.
  final double size;

  final bool done;
}

BreathMoment breathAt(BreathPattern pattern, Duration elapsed) {
  final totalMs = pattern.total.inMilliseconds;
  if (elapsed.inMilliseconds >= totalMs) {
    return BreathMoment(phase: BreathPhase.holdOut, phaseProgress: 1, cycle: pattern.cycles - 1, size: 0, done: true);
  }
  final cycleMs = pattern.cycleSeconds * 1000;
  final ms = elapsed.inMilliseconds < 0 ? 0 : elapsed.inMilliseconds;
  final cycle = ms ~/ cycleMs;
  var within = ms % cycleMs;
  final phases = <(BreathPhase, int)>[
    (BreathPhase.inhale, pattern.inSeconds * 1000),
    (BreathPhase.holdIn, pattern.holdInSeconds * 1000),
    (BreathPhase.exhale, pattern.outSeconds * 1000),
    (BreathPhase.holdOut, pattern.holdOutSeconds * 1000),
  ];
  for (final (phase, length) in phases) {
    if (length == 0) continue;
    if (within < length) {
      final p = within / length;
      // Eased, so the orb slows into the top and bottom of each breath instead of turning sharply.
      final eased = p * p * (3 - 2 * p);
      final size = switch (phase) {
        BreathPhase.inhale => eased,
        BreathPhase.holdIn => 1.0,
        BreathPhase.exhale => 1 - eased,
        BreathPhase.holdOut => 0.0,
      };
      return BreathMoment(phase: phase, phaseProgress: p, cycle: cycle, size: size, done: false);
    }
    within -= length;
  }
  return BreathMoment(phase: BreathPhase.holdOut, phaseProgress: 1, cycle: cycle, size: 0, done: false);
}

String breathPhaseLabel(BreathPhase phase) => switch (phase) {
  BreathPhase.inhale => 'Breathe in',
  BreathPhase.holdIn => 'Hold gently',
  BreathPhase.exhale => 'Breathe out',
  BreathPhase.holdOut => 'Rest',
};

/// The rhythm for a breathing guide; null for the others.
BreathPattern? breathPatternFor(ExerciseGuide guide) => switch (guide) {
  ExerciseGuide.breathing => const BreathPattern(inSeconds: 4, outSeconds: 4, cycles: 5),
  ExerciseGuide.longExhale => const BreathPattern(inSeconds: 4, outSeconds: 6, cycles: 5),
  ExerciseGuide.boxBreathing => const BreathPattern(inSeconds: 4, holdInSeconds: 4, outSeconds: 4, holdOutSeconds: 4, cycles: 4),
  _ => null,
};

/// One step of the 5-4-3-2-1 grounding: how many things to find, and through which sense.
class GroundingStep {
  const GroundingStep(this.count, this.prompt, this.hint);
  final int count;
  final String prompt;
  final String hint;
}

const groundingSteps = <GroundingStep>[
  GroundingStep(5, 'things you can see', 'Look around slowly. Tap each one as you find it.'),
  GroundingStep(4, 'things you can feel', 'Your clothes, the chair, the floor, the air on your skin.'),
  GroundingStep(3, 'things you can hear', 'Near sounds and far ones.'),
  GroundingStep(2, 'things you can smell', 'Or two smells you like to remember.'),
  GroundingStep(1, 'thing you can taste', 'Or take one slow sip of water.'),
];

/// A prompt in a writing exercise.
class WritingPrompt {
  const WritingPrompt(this.title, this.hint);
  final String title;
  final String hint;
}

List<WritingPrompt>? writingPromptsFor(ExerciseGuide guide) => switch (guide) {
  ExerciseGuide.gratitude => const [
    WritingPrompt('Something small that went okay today', 'A warm drink, a message, a minute of quiet.'),
    WritingPrompt('Someone or something you were glad of', 'It can be tiny.'),
    WritingPrompt('One thing about today you would keep', 'Only if one comes to mind.'),
  ],
  ExerciseGuide.reframe => const [
    WritingPrompt('What is the thought?', 'Write it the way it sounds in your head.'),
    WritingPrompt('What would you say to a friend who thought this?', 'Kinder, and probably truer.'),
    WritingPrompt('A gentler way to hold it', 'Not a cure. Just a bit more room.'),
  ],
  _ => null,
};

String exerciseIntro(ExerciseGuide guide) => switch (guide) {
  ExerciseGuide.breathing => 'Five slow breaths, in and out at an even pace. Follow the circle; there is nothing to get right.',
  ExerciseGuide.longExhale => 'Five breaths with a longer breath out than in, which helps the body settle. Follow the circle.',
  ExerciseGuide.boxBreathing => 'Four rounds of breathing in, holding, out, and resting, each for four counts. Follow the circle.',
  ExerciseGuide.grounding => 'Bring yourself back to the room through your senses, from five things down to one.',
  ExerciseGuide.gratitude => 'Three short lines about what was good, however small. Skip any that do not come.',
  ExerciseGuide.reframe => 'Look at a hard thought from a little further back. Three short questions, at your pace.',
};

/// Whether the guide asks the person to type, so what they write is checked for safety like all typed words.
bool exerciseTakesWords(ExerciseGuide guide) => writingPromptsFor(guide) != null;
