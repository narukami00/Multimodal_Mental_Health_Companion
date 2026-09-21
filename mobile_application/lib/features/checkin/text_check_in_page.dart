import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/theme/app_theme.dart';
import '../journal/session_detail_page.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';

class TextCheckInPage extends StatefulWidget {
  const TextCheckInPage({
    required this.sessionController,
    required this.safetyController,
    super.key,
  });

  final SessionController sessionController;
  final SafetyController safetyController;

  @override
  State<TextCheckInPage> createState() => _TextCheckInPageState();
}

class _TextCheckInPageState extends State<TextCheckInPage> {
  static const _moods = ['Steady', 'Bright', 'Tender', 'Wobbly', 'Quiet'];

  final _textController = TextEditingController();
  String? _selectedMood;
  bool _isSaving = false;
  bool _safetyAcknowledged = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canSave => _selectedMood != null || _textController.text.trim().isNotEmpty;

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
                assessment: assessment,
                regionCode: Localizations.localeOf(context).countryCode ?? 'GLOBAL',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text check-in'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
          children: [
            Text(
              'What feels present right now?',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'A word, a mood, or a few sentences are all enough.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.mutedInk,
                  ),
            ),
            const SizedBox(height: 26),
            Text('A quick word for it', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final mood in _moods)
                  ChoiceChip(
                    label: Text(mood),
                    selected: _selectedMood == mood,
                    selectedColor: AppColors.amber,
                    backgroundColor: Colors.white.withValues(alpha: 0.85),
                    labelStyle: TextStyle(
                      color: _selectedMood == mood ? AppColors.deepAmber : AppColors.mutedInk,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (selected) {
                      setState(() => _selectedMood = selected ? mood : null);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 26),
            Text('Anything else?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              onChanged: (_) {
                setState(() {
                  _safetyAcknowledged = false;
                });
              },
              minLines: 6,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Let the thought land here…',
                hintStyle: const TextStyle(color: AppColors.mutedInk),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.amber, width: 2),
                ),
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(22, 8, 22, 18),
        child: FilledButton.icon(
          key: const ValueKey('text-check-in-save'),
          onPressed: _canSave && !_isSaving ? _save : null,
          icon: _isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: const Text('Keep this moment'),
        ),
      ),
    );
  }
}
