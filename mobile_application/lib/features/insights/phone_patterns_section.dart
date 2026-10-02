import 'package:flutter/material.dart';

import '../../core/models/daily_features.dart';
import '../../domain/footprint/phone_noticings.dart';
import '../footprint/phone_patterns_controller.dart';
import '../profile/phone_patterns_page.dart';
import '../profile/profile_controller.dart';

/// The real, data-backed part of Insights: what the person's own phone use has
/// been, in plain statements, or an honest account of why there is nothing yet.
///
/// Three states and no filler. Not turned on: a quiet invitation. Turned on but
/// still learning: how many days have been read. Enough days: statements about
/// what is usual. It never shows a number it does not have.
class PhonePatternsSection extends StatefulWidget {
  const PhonePatternsSection({
    required this.phonePatterns,
    required this.profileController,
    this.clock,
    super.key,
  });

  final PhonePatternsController phonePatterns;
  final ProfileController profileController;
  final DateTime Function()? clock;

  @override
  State<PhonePatternsSection> createState() => _PhonePatternsSectionState();
}

class _PhonePatternsSectionState extends State<PhonePatternsSection> {
  List<DailyFeatures> _rows = const [];

  PhonePatternsController get _patterns => widget.phonePatterns;

  @override
  void initState() {
    super.initState();
    _patterns.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _patterns.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final rows = await _patterns.storedDays();
    if (mounted) setState(() => _rows = rows);
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhonePatternsPage(
          phonePatterns: _patterns,
          profileController: widget.profileController,
        ),
      ),
    );
  }

  static IconData _icon(NoticingKind kind) => switch (kind) {
    NoticingKind.screen => Icons.smartphone_rounded,
    NoticingKind.rhythm => Icons.bedtime_rounded,
    NoticingKind.apps => Icons.donut_small_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final on = _patterns.status == PhonePatternsStatus.on;
    final result = phoneNoticings(_rows, (widget.clock ?? DateTime.now)());

    final Widget body;
    if (!on && result.isEmpty) {
      body = _invitation(
        'Phone patterns is off, so nothing is being read. Turn it on and Solace '
        'can show you your own usual: screen time, your nights, and where phone '
        'time goes.',
        'See what this would show',
      );
    } else if (result.isLearning) {
      body = _learning(result);
    } else {
      body = Column(
        children: [
          for (final noticing in result.noticings) ...[
            _card(noticing),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('phone-section-details'),
              onPressed: _open,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF96620C),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See the details',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('phone-patterns-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 22, 2, 10),
          child: Text(
            'PHONE PATTERNS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: Color(0xFFA69883),
            ),
          ),
        ),
        body,
      ],
    );
  }

  Widget _shell({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0x143B2F26)),
    ),
    child: child,
  );

  Widget _invitation(String text, String action) => _shell(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          key: const ValueKey('phone-section-off'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: Color(0xFF5E513F),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('phone-section-open'),
          onPressed: _open,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF96620C),
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            action,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  Widget _learning(PhoneNoticings result) {
    final read = result.daysRead;
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Still getting to know your usual.',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3A3125),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$read of ${result.daysNeeded} days read. Solace says nothing about '
            'what is usual for you until it has seen enough days to be '
            'right.',
            key: const ValueKey('phone-section-learning'),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: Color(0xFF6B5B43),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (read / result.daysNeeded).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFFF3E7CE),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB534)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(PhoneNoticing noticing) => _shell(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3DC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_icon(noticing.kind), size: 19, color: const Color(0xFFB57A12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                noticing.meta,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: Color(0xFFBCAC8E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                noticing.text,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  color: Color(0xFF3A3125),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
