import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../domain/exercises/exercise_plan.dart';
import '../art/activity_art.dart';

/// A guided exercise, full screen and quiet: a breathing circle to follow, the five senses to walk through, or
/// a few short questions to write against. Nothing is timed against the person and nothing they write is kept.
///
/// Pops `true` when they reach the end and choose to finish, and `false` when they stop early.
class ExercisePage extends StatefulWidget {
  const ExercisePage({required this.guide, required this.title, this.onWords, super.key});

  final ExerciseGuide guide;
  final String title;

  /// Called with what was written when a writing exercise ends, so the words get the same safety check as
  /// anything else typed in Solace. They are never stored by this page.
  final Future<void> Function(String words)? onWords;

  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

enum _Stage { intro, run, done }

class _ExercisePageState extends State<ExercisePage> with SingleTickerProviderStateMixin {
  _Stage _stage = _Stage.intro;
  late final BreathPattern? _pattern = breathPatternFor(widget.guide);
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _pattern?.total ?? const Duration(seconds: 1),
  );

  // Grounding.
  int _step = 0;
  int _found = 0;

  // Writing.
  late final List<WritingPrompt>? _prompts = writingPromptsFor(widget.guide);
  late final List<TextEditingController> _answers = [
    for (final _ in _prompts ?? const <WritingPrompt>[]) TextEditingController(),
  ];
  int _prompt = 0;

  ArtPalette get _palette => ActivityArt.paletteFor(ActivityType.mindfulness);

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _stage = _Stage.done);
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  void _begin() {
    setState(() => _stage = _Stage.run);
    if (_pattern != null) _clock.forward(from: 0);
  }

  void _nextGrounding() {
    if (_step == groundingSteps.length - 1) {
      setState(() => _stage = _Stage.done);
    } else {
      setState(() {
        _step++;
        _found = 0;
      });
    }
  }

  Future<void> _nextPrompt() async {
    FocusScope.of(context).unfocus();
    if (_prompt < _answers.length - 1) {
      setState(() => _prompt++);
      return;
    }
    final words = _answers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).join('\n');
    if (words.isNotEmpty) await widget.onWords?.call(words);
    if (mounted) setState(() => _stage = _Stage.done);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.skyTop, palette.skyBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: IconButton(
                    key: const ValueKey('exercise-stop'),
                    tooltip: 'Stop',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded, color: palette.ink),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: KeyedSubtree(key: ValueKey(_stage), child: _body(palette)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ArtPalette palette) {
    return switch (_stage) {
      _Stage.intro => _intro(palette),
      _Stage.done => _finish(palette),
      _Stage.run => switch (widget.guide) {
        ExerciseGuide.grounding => _grounding(palette),
        ExerciseGuide.gratitude || ExerciseGuide.reframe => _writing(palette),
        _ => _breathing(palette),
      },
    };
  }

  Widget _frame({required List<Widget> children}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  TextStyle _title(ArtPalette p) => TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.2, color: p.ink);
  TextStyle _text(ArtPalette p) => TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.5, color: p.ink.withValues(alpha: 0.78));

  Widget _intro(ArtPalette p) {
    return _frame(
      children: [
        _OrbHint(palette: p),
        const SizedBox(height: 28),
        Text(widget.title, textAlign: TextAlign.center, style: _title(p)),
        const SizedBox(height: 12),
        Text(exerciseIntro(widget.guide), textAlign: TextAlign.center, style: _text(p)),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: FilledButton(key: const ValueKey('exercise-begin'), onPressed: _begin, child: const Text('Begin')),
        ),
      ],
    );
  }

  Widget _breathing(ArtPalette p) {
    final pattern = _pattern!;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final moment = breathAt(pattern, pattern.total * _clock.value);
        return _frame(
          children: [
            SizedBox(
              height: 300,
              width: double.infinity,
              child: CustomPaint(painter: _OrbPainter(size: moment.size, palette: p)),
            ),
            const SizedBox(height: 16),
            Text(breathPhaseLabel(moment.phase), key: const ValueKey('breath-phase'), style: _title(p)),
            const SizedBox(height: 8),
            Text('Breath ${moment.cycle + 1} of ${pattern.cycles}', style: _text(p)),
          ],
        );
      },
    );
  }

  Widget _grounding(ArtPalette p) {
    final step = groundingSteps[_step];
    final ready = _found >= step.count;
    return _frame(
      children: [
        Text('${step.count}', key: const ValueKey('grounding-count'), style: TextStyle(fontSize: 72, fontWeight: FontWeight.w800, height: 1, color: p.ink)),
        const SizedBox(height: 8),
        Text(step.prompt, textAlign: TextAlign.center, style: _title(p)),
        const SizedBox(height: 10),
        Text(step.hint, textAlign: TextAlign.center, style: _text(p)),
        const SizedBox(height: 26),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            for (var i = 0; i < step.count; i++)
              _Dot(
                key: ValueKey('dot-$i'),
                filled: i < _found,
                color: p.a,
                onTap: () => setState(() => _found = _found == i + 1 ? i : i + 1),
              ),
          ],
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('grounding-next'),
            onPressed: _nextGrounding,
            child: Text(_step == groundingSteps.length - 1 ? 'Finish' : ready ? 'Next' : 'Skip to next'),
          ),
        ),
      ],
    );
  }

  Widget _writing(ArtPalette p) {
    final prompt = _prompts![_prompt];
    final last = _prompt == _answers.length - 1;
    return _frame(
      children: [
        Text('${_prompt + 1} of ${_answers.length}', style: _text(p)),
        const SizedBox(height: 10),
        Text(prompt.title, textAlign: TextAlign.center, style: _title(p)),
        const SizedBox(height: 18),
        TextField(
          key: ValueKey('answer-$_prompt'),
          controller: _answers[_prompt],
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: prompt.hint,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('writing-next'),
            onPressed: _nextPrompt,
            child: Text(last ? 'Finish' : 'Next'),
          ),
        ),
        const SizedBox(height: 10),
        Text('What you write stays on this screen. Nothing is saved.', textAlign: TextAlign.center, style: _text(p).copyWith(fontSize: 12)),
      ],
    );
  }

  Widget _finish(ArtPalette p) {
    return _frame(
      children: [
        _OrbHint(palette: p),
        const SizedBox(height: 28),
        Text('Nicely done.', style: _title(p)),
        const SizedBox(height: 10),
        Text('Take a moment before you go back.', textAlign: TextAlign.center, style: _text(p)),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('exercise-finish'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Back to my day'),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.filled, required this.color, required this.onTap, super.key});

  final bool filled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.white.withValues(alpha: 0.7),
            border: Border.all(color: color, width: 2),
          ),
          child: filled ? const Icon(Icons.check_rounded, color: Colors.white, size: 24) : null,
        ),
      ),
    );
  }
}

/// A still, soft circle for the screens that are not mid-breath.
class _OrbHint extends StatelessWidget {
  const _OrbHint({required this.palette});
  final ArtPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: 150,
      child: CustomPaint(painter: _OrbPainter(size: 0.55, palette: palette)),
    );
  }
}

/// The breathing circle: soft rings around a core that grows as the lungs fill.
class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.size, required this.palette});

  final double size;
  final ArtPalette palette;

  @override
  void paint(Canvas canvas, Size box) {
    final centre = box.center(Offset.zero);
    final limit = (box.shortestSide / 2).clamp(40.0, 150.0);
    final core = limit * (0.42 + 0.5 * size);
    for (var i = 3; i >= 1; i--) {
      canvas.drawCircle(
        centre,
        core + i * limit * 0.09 * (0.6 + size * 0.6),
        Paint()..color = palette.c.withValues(alpha: 0.13 * (4 - i)),
      );
    }
    canvas.drawCircle(
      centre,
      core,
      Paint()
        ..shader = RadialGradient(
          colors: [palette.c.withValues(alpha: 0.95), palette.a.withValues(alpha: 0.9)],
          center: const Alignment(-0.3, -0.35),
        ).createShader(Rect.fromCircle(center: centre, radius: core)),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.size != size || old.palette != palette;
}
