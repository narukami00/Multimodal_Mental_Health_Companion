import 'package:flutter/material.dart';

import '../../core/models/emotion_result.dart';
import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({required this.session, this.onDelete, super.key});

  final SessionRecord session;

  /// When given, the entry can be deleted from here. Called once the person has
  /// confirmed; the page closes afterwards.
  final Future<void> Function(SessionRecord session)? onDelete;

  static const _ink = Color(0xFF3A3125);
  static const _softInk = Color(0xFF8A7A61);
  static const _warm = Color(0xFFFFB534);

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(session.createdAt);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(session.createdAt));
    final labels = session.emotionResults
        .expand((result) => result.labels ?? const <EmotionLabel>[])
        .toList();
    final topLabel = labels
        .map((item) => item.label)
        .firstWhere(
          (item) => item.isNotEmpty,
          orElse: () => 'still getting to know this signal',
        );
    final modeLabel = switch (session.mode) {
      CaptureMode.text => 'Text check-in',
      CaptureMode.voice => 'Voice check-in',
      CaptureMode.video => 'Video check-in',
    };

    return Scaffold(
      backgroundColor: const Color(0xFFFEFCE8),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFEFCE8), Color(0xFFFFFBEC)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: Color(0xFF8A6B33),
                          ),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(40, 40),
                            maximumSize: const Size(40, 40),
                            backgroundColor: const Color(0xFFFFF6E0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$date · $time',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                              Text(
                                modeLabel,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _softInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF6E0),
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x1F7A5A28),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _modeIcon(session.mode),
                                size: 15,
                                color: const Color(0xFFC98A2E),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                modeLabel.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: Color(0xFFA97410),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SummaryCard(
                            label: topLabel,
                            labels: labels,
                            mood: session.mood,
                            mode: session.mode,
                          ),
                          const SizedBox(height: 18),
                          if (session.text?.trim().isNotEmpty ?? false) ...[
                            const Text(
                              'Your words',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                20,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFDF6),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0x4DE2C185),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0x1F96641E),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '“',
                                    style: TextStyle(
                                      fontSize: 34,
                                      height: 0.6,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0x66FFB534),
                                    ),
                                  ),
                                  Text(
                                    session.text!.trim(),
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF483523),
                                      height: 1.55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _warm.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _warm.withValues(alpha: 0.30),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFFA97410),
                                  size: 20,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Solace offers reflections, not diagnoses. Model signals are optional and may be incomplete.',
                                    style: TextStyle(
                                      color: Color(0xFF8A6112),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (onDelete != null) ...[
                            const SizedBox(height: 14),
                            Center(
                              child: TextButton.icon(
                                key: const ValueKey('delete-entry'),
                                onPressed: () => _confirmDelete(context),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFB5503C),
                                ),
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                label: const Text(
                                  'Delete this entry',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'It is removed from this phone, along with any moment that came from '
          'it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const ValueKey('delete-entry-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await onDelete!(session);
    if (context.mounted) Navigator.of(context).maybePop();
  }

  IconData _modeIcon(CaptureMode mode) {
    return switch (mode) {
      CaptureMode.text => Icons.chat_bubble_outline_rounded,
      CaptureMode.voice => Icons.graphic_eq_rounded,
      CaptureMode.video => Icons.videocam_outlined,
    };
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.labels,
    required this.mood,
    required this.mode,
  });

  final String label;
  final List<EmotionLabel> labels;
  final String? mood;
  final CaptureMode mode;

  @override
  Widget build(BuildContext context) {
    final modeLabel = switch (mode) {
      CaptureMode.text => 'Text check-in',
      CaptureMode.voice => 'Voice check-in',
      CaptureMode.video => 'Video check-in',
    };
    final headline = label == 'steady'
        ? 'Mostly steady, with pockets of ease'
        : 'Mostly ${_humanize(label)}';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x4DE2C185)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1F96641E),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(height: 10, color: const Color(0xFF8FB083)),
              ),
              Expanded(
                flex: 2,
                child: Container(height: 10, color: const Color(0xFFFFB534)),
              ),
              Expanded(
                flex: 1,
                child: Container(height: 10, color: const Color(0xFFFF7F50)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OVERALL FEEL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Color(0xFF9C8B72),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A3125),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A soft summary from the signals available in this session.',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A7A61),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in labels.take(2))
                      _Pill(
                        label: item.score != null
                            ? '${_humanize(item.label)} ${(item.score! * 100).round()}%'
                            : _humanize(item.label),
                        color: _stateColor(item.label),
                      ),
                    _Pill(label: modeLabel, dashed: true),
                    if (mood != null)
                      _Pill(label: _humanize(mood!), dashed: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _stateColor(String value) {
    if (const {'calm', 'steady', 'reflective'}.contains(value)) {
      return const Color(0xFF6E8F63);
    }
    if (const {'tense', 'wobbly', 'hesitant'}.contains(value)) {
      return const Color(0xFFC05B33);
    }
    return const Color(0xFFA97410);
  }

  String _humanize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.color, this.dashed = false});

  final String label;
  final Color? color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? const Color(0xFFA97410);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: dashed
            ? Border.all(color: const Color(0xFFEBC98A), width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
