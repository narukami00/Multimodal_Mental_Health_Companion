import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/widgets/page_back_button.dart';
import '../consent/emotion_consent_sheets.dart';
import '../journal/journal_ui.dart';
import '../journal/session_detail_page.dart';
import 'check_in_mode_page.dart';
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
      _textController.text.trim().isNotEmpty;

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

    // The words are read for emotion by the companion server only with the person's yes (asked once).
    final consent = CheckInModePage.consent;
    if (text != null && consent != null && mounted) {
      await askEmotionConsent(context, consent);
    }

    final session = await widget.sessionController.saveSession(
      mode: CaptureMode.text,
      text: text,
    );

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailPage(
          session: session,
          onDelete: (s) => widget.sessionController.deleteSession(s.id),
          onReanalyze: widget.sessionController.reanalyze,
        ),
      ),
    );
  }

  int get _wordCount {
    final t = _textController.text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  /// A quiet line under the box that changes as they write. It never says how much is enough.
  String _nudge(int words) {
    if (words == 0) return 'No rush. A single word is enough.';
    if (words < 6) return 'Good start. Keep going if you like.';
    if (words < 25) return "That's it. Let it come.";
    return 'Whenever you feel done, keep this moment.';
  }

  /// Begins (or continues) the entry with a sentence starter, which is often the hardest part.
  void _begin(String starter) {
    final current = _textController.text;
    final spaced = current.isEmpty || current.endsWith(' ') || current.endsWith('\n') ? current : '$current ';
    final text = '$spaced$starter ';
    setState(() {
      _textController.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      _safetyAcknowledged = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _canSave && !_isSaving;
    final nudge = _nudge(_wordCount);
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8EC),
      body: JournalBackdrop(
        tint: JournalTint.text,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  const Row(
                    children: [
                      PageBackButton(),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Text check-in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(colors: [_amber, _coral]),
                          boxShadow: [BoxShadow(color: _coral.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))],
                        ),
                        child: const Icon(Icons.edit_rounded, size: 22, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'What feels present right now?',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A word or a few sentences are all enough.',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _softInk, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'What is on your mind?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink),
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
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink),
                    decoration: InputDecoration(
                      hintText: 'Let the thought land here…',
                      hintStyle: TextStyle(color: _softInk.withValues(alpha: 0.7), fontWeight: FontWeight.w600),
                      filled: true,
                      fillColor: _cream,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0x42FFB534))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0x42FFB534))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: _amber, width: 2)),
                      contentPadding: const EdgeInsets.all(18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: Text(
                        nudge,
                        key: ValueKey(nudge),
                        style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w700, color: _softInk),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'NEED A PLACE TO START?',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: _softInk),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final starter in sentenceStarters(DateTime.now().hour))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _StarterChip(key: ValueKey('starter-$starter'), label: starter, onTap: () => _begin(starter)),
                          ),
                      ],
                    ),
                  ),
                  if (widget.profileController != null) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      key: const ValueKey('rest-today-checkin'),
                      onPressed: _declareRest,
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF96620C)),
                      child: const Text('Rest today instead', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
                        Flexible(
                          child: Text(
                          'Keep this moment',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: enabled
                                ? Colors.white
                                : const Color(0x804A3728),
                          ),
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

/// A sentence starter, tapped to begin the entry.
class _StarterChip extends StatelessWidget {
  const _StarterChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.75),
      shape: const StadiumBorder(side: BorderSide(color: Color(0x55FFB534))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6E5A2E))),
        ),
      ),
    );
  }
}
