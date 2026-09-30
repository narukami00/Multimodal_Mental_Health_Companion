import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/session_input.dart';
import '../../core/models/safety_assessment.dart';
import '../journal/session_detail_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';

class TextCheckInPage extends StatefulWidget {
  const TextCheckInPage({
    required this.sessionController,
    required this.safetyController,
    this.profileController,
    super.key,
  });

  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController? profileController;

  @override
  State<TextCheckInPage> createState() => _TextCheckInPageState();
}

class _TextCheckInPageState extends State<TextCheckInPage> {
  static const _ink = Color(0xFF3A3125);
  static const _softInk = Color(0xFF6E6252);
  static const _cream = Color(0xFFFFFDF6);
  static const _amber = Color(0xFFFFB534);
  static const _coral = Color(0xFFFF7F50);

  final _textController = TextEditingController();
  String? _selectedMood;
  bool _isSaving = false;
  bool _safetyAcknowledged = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// Records today as rest and leaves. One tap, no reason, nothing saved.
  ///
  /// Rest is a legitimate choice, not a lesser check-in, so it is offered here
  /// beside the check-in rather than buried in settings.
  Future<void> _declareRest() async {
    final controller = widget.profileController;
    if (controller == null) return;

    await controller.declareRestDay(DateTime.now());
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Rest noted. That counts.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
  }

  bool get _canSave =>
      _selectedMood != null || _textController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave || _isSaving) return;
    setState(() => _isSaving = true);

    final text = _textController.text.trim().isEmpty
        ? null
        : _textController.text.trim();
    if (text != null && !_safetyAcknowledged) {
      final assessment = await widget.safetyController.assessText(
        source: 'text_check_in',
        text: text,
      );
      if (assessment.level != SafetyLevel.clear) {
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SupportResourcesPage(
                safetyController: widget.safetyController,
                profileController: widget.profileController,
                assessment: assessment,
              ),
            ),
          );
          if (mounted) {
            setState(() {
              _isSaving = false;
              _safetyAcknowledged = true;
            });
          }
        }
        return;
      }
    }

    final session = await widget.sessionController.saveSession(
      mode: CaptureMode.text,
      text: text,
      mood: _selectedMood?.toLowerCase(),
    );

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailPage(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _canSave && !_isSaving;
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8EC),
      body: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFDF8EC),
                      Color(0xFFFBF3E4),
                      Color(0xFFFBEFE3),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -70,
              right: -60,
              child: _GlowBlob(
                color: _amber.withValues(alpha: 0.32),
                size: 260,
              ),
            ),
            Positioned(
              bottom: -80,
              left: -70,
              child: _GlowBlob(
                color: _coral.withValues(alpha: 0.26),
                size: 300,
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                              color: _ink,
                            ),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              maximumSize: const Size(44, 44),
                              backgroundColor: _cream.withValues(alpha: 0.8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: _amber.withValues(alpha: 0.25),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Text check-in',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'What feels present right now?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A word, a mood, or a few sentences are all enough.',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _softInk,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'A quick word for it',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: [
                          for (final mood in Moods.values)
                            _MoodPill(
                              label: mood,
                              selected: _selectedMood == mood,
                              onTap: () {
                                setState(
                                  () => _selectedMood = _selectedMood == mood
                                      ? null
                                      : mood,
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'Anything else?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _textController,
                        onChanged: (_) {
                          setState(() {
                            _safetyAcknowledged = false;
                          });
                        },
                        minLines: 5,
                        maxLines: 8,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Let the thought land here…',
                          hintStyle: TextStyle(
                            color: _softInk.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                          filled: true,
                          fillColor: _cream,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: Color(0x42FFB534),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: Color(0x42FFB534),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: _amber,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(18),
                        ),
                      ),
                      if (widget.profileController != null) ...[
                        const SizedBox(height: 14),
                        TextButton(
                          key: const ValueKey('rest-today-checkin'),
                          onPressed: _declareRest,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF96620C),
                          ),
                          child: const Text(
                            'Rest today instead',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(22, 8, 22, 18),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: enabled
                    ? const LinearGradient(colors: [_amber, _coral])
                    : null,
                color: enabled ? null : const Color(0x1F4A3728),
                borderRadius: BorderRadius.circular(24),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: _coral.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : const [],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('text-check-in-save'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: enabled ? _save : null,
                  child: SizedBox(
                    height: 54,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isSaving)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: enabled
                                ? Colors.white
                                : const Color(0x804A3728),
                          ),
                        const SizedBox(width: 9),
                        Text(
                          'Keep this moment',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: enabled
                                ? Colors.white
                                : const Color(0x804A3728),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodPill extends StatelessWidget {
  const _MoodPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFFFB534), Color(0xFFFF9F45)],
                  )
                : null,
            color: selected ? null : const Color(0xFFFFFDF6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0x59FFB534)
                  : const Color(0x38B28028),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected
                  ? const Color(0xFF3A3125)
                  : const Color(0xFF6E6252),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}
