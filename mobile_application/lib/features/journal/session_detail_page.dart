import 'package:flutter/material.dart';

import '../../core/models/memory_moment.dart';
import '../../core/models/session_input.dart';
import '../../domain/memory/moment_entry.dart';
import '../memory/keep_moment.dart';
import '../../core/models/session_record.dart';
import '../../core/widgets/page_back_button.dart';
import 'emotion_reading_card.dart';
import 'reading_status.dart';

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({
    required this.session,
    this.onDelete,
    this.onReanalyze,
    super.key,
  });

  final SessionRecord session;

  /// When given, the entry can be deleted from here. Called once the person has
  /// confirmed; the page closes afterwards.
  final Future<void> Function(SessionRecord session)? onDelete;

  /// When given, an entry with no model reading (an older entry, or one made without the server) can be
  /// read now. Returns the updated entry, or null when no reading could be made.
  final Future<SessionRecord?> Function(SessionRecord session)? onReanalyze;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  late SessionRecord session = widget.session;
  bool _reading = false;

  Future<void> Function(SessionRecord session)? get onDelete => widget.onDelete;

  static const _ink = Color(0xFF3A3125);
  static const _softInk = Color(0xFF8A7A61);
  static const _warm = Color(0xFFFFB534);

  Widget _readingSection() {
    if (session.awaitingRecording) {
      return Container(
        key: const ValueKey('entry-waiting'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF6E4C8)),
        ),
        child: const Text(
          'This recording is kept safely on your phone and will be written down and read as soon as the '
          'companion server is reachable. Then the recording is deleted from your phone.',
          style: TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600, color: _ink),
        ),
      );
    }
    final r = session.reading;
    if (r != null) return EmotionReadingCard(reading: r);
    final canRead =
        widget.onReanalyze != null &&
        (session.text?.trim().isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NoReadingCard(),
        if (canRead)
          TextButton(
            key: const ValueKey('reanalyze'),
            onPressed: _reading ? null : _reanalyze,
            child: Text(_reading ? 'Reading…' : 'Read this entry now'),
          ),
      ],
    );
  }

  Future<void> _reanalyze() async {
    setState(() => _reading = true);
    final updated = await widget.onReanalyze!(session);
    final why = updated == null ? await explainNoReading() : null; // what is actually in the way, not a guess
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (updated != null) session = updated;
    });
    if (updated == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(why!),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeLabel = switch (session.mode) {
      CaptureMode.text => 'Text check-in',
      CaptureMode.voice => 'Voice check-in',
      CaptureMode.video => 'Video check-in',
    };
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(session.createdAt);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(session.createdAt));

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
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                // Same 22px inset as the main pages, so cards line up app-wide.
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                child: Row(
                  children: [
                    const PageBackButton(),
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
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _readingSection(),
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
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFDF6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0x4DE2C185)),
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
                        if (KeepMoment.available) ...[
                          const SizedBox(height: 12),
                          _keepButton(context),
                        ],
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
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
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
    );
  }

  /// Offers to keep something from this entry as a moment: no model involved, so it cannot fail.
  Widget _keepButton(BuildContext context) {
    final text = session.text!.trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('keep-moment'),
        onPressed: () async {
          await KeepMoment.open(
            context,
            MomentEntry(
              text: text,
              source: text.length > 80 ? MomentSource.journal : MomentSource.checkIn,
              sourceRef: session.id,
              at: session.createdAt,
              moodWord: session.effectiveMood,
              reading: session.reading,
            ),
          );
          if (mounted) setState(() {});
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF96620C),
          side: const BorderSide(color: Color(0x66FFB534)),
          shape: const StadiumBorder(),
        ),
        icon: Icon(
          KeepMoment.isKept(session.id) ? Icons.check_rounded : Icons.auto_awesome_rounded,
          size: 17,
        ),
        label: Text(
          KeepMoment.isKept(session.id) ? 'Kept as a moment. Keep another' : 'Keep as a moment',
          style: const TextStyle(fontWeight: FontWeight.w800),
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
