import 'package:flutter/material.dart';

import '../../core/models/chat_conversation_record.dart';
import '../../domain/chat/conversation_breakdown.dart';

/// Compact, scannable list of inferred emotional shifts inside
/// ConversationBreakdownPage. Each shift starts collapsed with a concise status
/// badge and expands one-at-a-time on tap (or via "Review next") to show
/// single-line segmented agreement pills rather than stacking repetitive chip
/// walls down the entire page.
class ShiftsReviewList extends StatefulWidget {
  const ShiftsReviewList({
    required this.shifts,
    required this.reviews,
    required this.onSaveReview,
    super.key,
  });

  final List<MoodShift> shifts;
  final List<TrajectoryShiftReview> reviews;
  final ValueChanged<TrajectoryShiftReview> onSaveReview;

  @override
  State<ShiftsReviewList> createState() => _ShiftsReviewListState();
}

class _ShiftsReviewListState extends State<ShiftsReviewList> {
  String? _expandedShiftId;

  static const _ink = Color(0xFF3A3125);
  static const _soft = Color(0xFF8A7A61);
  static const _sage = Color(0xFF3F9A7C);
  static const _coral = Color(0xFFD9825B);
  static const _amber = Color(0xFFD99A2B);

  TrajectoryShiftReview? _reviewFor(MoodShift s) {
    for (final r in widget.reviews) {
      if (r.shiftId == s.shiftId && r.evidenceVersion == s.evidenceVersion) {
        return r;
      }
    }
    return null;
  }

  MoodShift? get _firstUnreviewed {
    for (final s in widget.shifts) {
      if (_reviewFor(s) == null) return s;
    }
    return null;
  }

  MoodShift? _nextUnreviewedAfter(String shiftId) {
    final idx = widget.shifts.indexWhere((s) => s.shiftId == shiftId);
    for (var i = idx + 1; i < widget.shifts.length; i++) {
      if (_reviewFor(widget.shifts[i]) == null) return widget.shifts[i];
    }
    for (var i = 0; i < idx; i++) {
      if (_reviewFor(widget.shifts[i]) == null) return widget.shifts[i];
    }
    return null;
  }

  (String label, Color color) _statusMeta(TrajectoryShiftReview? review) {
    if (review == null) {
      return ('Tap to review', _amber);
    }
    return switch (review.shiftFit) {
      ShiftAgreement.agrees => ('Fits', _sage),
      ShiftAgreement.disagrees => ('Not quite', _coral),
      ShiftAgreement.unsure => ('Unsure', const Color(0xFF6B7280)),
      ShiftAgreement.skipped => ('Skipped', const Color(0xFF9E9280)),
    };
  }

  void _saveShiftFit(
    MoodShift shift,
    TrajectoryShiftReview? existing,
    ShiftAgreement fit,
  ) {
    final next = TrajectoryShiftReview(
      shiftId: shift.shiftId,
      fromMessageId: shift.from.message.id,
      toMessageId: shift.to.message.id,
      evidenceVersion: shift.evidenceVersion,
      shiftFit: fit,
      reasonFit: fit == ShiftAgreement.agrees || fit == ShiftAgreement.unsure
          ? existing?.reasonFit
          : null,
      proposedContext: shift.proposedContext,
      userCorrection: existing?.userCorrection,
      reviewedAt: DateTime.now(),
    );
    widget.onSaveReview(next);
  }

  void _saveReasonFit(
    MoodShift shift,
    TrajectoryShiftReview? existing,
    ShiftAgreement reasonFit,
  ) {
    final next = TrajectoryShiftReview(
      shiftId: shift.shiftId,
      fromMessageId: shift.from.message.id,
      toMessageId: shift.to.message.id,
      evidenceVersion: shift.evidenceVersion,
      shiftFit: existing?.shiftFit ?? ShiftAgreement.agrees,
      reasonFit: reasonFit,
      proposedContext: shift.proposedContext,
      userCorrection: existing?.userCorrection,
      reviewedAt: DateTime.now(),
    );
    widget.onSaveReview(next);
  }

  Widget _segmentedBar({
    required String prefix,
    required ShiftAgreement? selected,
    required ValueChanged<ShiftAgreement> onPick,
  }) {
    const choices = [
      (ShiftAgreement.agrees, 'Yes', _sage),
      (ShiftAgreement.disagrees, 'Not quite', _coral),
      (ShiftAgreement.unsure, 'Unsure', Color(0xFF6B7280)),
      (ShiftAgreement.skipped, 'Skip', Color(0xFF9E9280)),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF6EFE0),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x26C7A977)),
      ),
      child: Row(
        children: [
          for (final (value, label, accent) in choices)
            Expanded(
              child: GestureDetector(
                key: ValueKey('$prefix-${value.name}'),
                onTap: () => onPick(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selected == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: selected == value
                        ? Border.all(color: accent.withValues(alpha: 0.45))
                        : null,
                    boxShadow: selected == value
                        ? const [
                            BoxShadow(
                              color: Color(0x1478501E),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          selected == value ? FontWeight.w800 : FontWeight.w600,
                      color: selected == value ? accent : _soft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reviewedCount =
        widget.shifts.where((s) => _reviewFor(s) != null).length;
    final nextPending = _firstUnreviewed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: nextPending == null
                    ? const Color(0x1F3F9A7C)
                    : const Color(0x22FFB534),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    nextPending == null
                        ? Icons.check_circle_rounded
                        : Icons.tune_rounded,
                    size: 14,
                    color: nextPending == null ? _sage : _amber,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$reviewedCount of ${widget.shifts.length} reviewed',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: nextPending == null ? _sage : const Color(0xFF7D5007),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (nextPending != null)
              TextButton.icon(
                key: const ValueKey('shifts-review-next'),
                onPressed: () =>
                    setState(() => _expandedShiftId = nextPending.shiftId),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFF7D5007),
                  backgroundColor: const Color(0xFFFFF4DC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                icon: const Icon(Icons.rate_review_outlined, size: 15),
                label: const Text(
                  'Review next',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.shifts.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildShiftTile(widget.shifts[i]),
        ],
      ],
    );
  }

  Widget _buildShiftTile(MoodShift s) {
    final review = _reviewFor(s);
    final isExpanded = _expandedShiftId == s.shiftId;
    final (statusLabel, statusColor) = _statusMeta(review);
    final nextPending = _nextUnreviewedAfter(s.shiftId);
    final showReason = s.proposedContext != null &&
        review?.shiftFit != ShiftAgreement.disagrees &&
        review?.shiftFit != ShiftAgreement.skipped;

    return AnimatedContainer(
      key: ValueKey('shift-row-${s.shiftId}'),
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isExpanded ? const Color(0xFFFFFDF8) : const Color(0xFFFFF9EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? const Color(0x99FFB534)
              : const Color(0x33C7A977),
          width: isExpanded ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('shift-toggle-${s.shiftId}'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() {
              _expandedShiftId = isExpanded ? null : s.shiftId;
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: s.lighter
                              ? const Color(0xFFEDF6EE)
                              : const Color(0xFFFDEEE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              s.lighter
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 14,
                              color: s.lighter
                                  ? const Color(0xFF426A38)
                                  : const Color(0xFF9C4E2C),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${s.from.word} → ${s.to.word}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: s.lighter
                                    ? const Color(0xFF426A38)
                                    : const Color(0xFF9C4E2C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: _soft,
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '"${s.to.message.spokenText}"',
                    maxLines: isExpanded ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: Color(0x26C7A977)),
                  const SizedBox(height: 10),
                  const Text(
                    'Did it feel like a shift here?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _segmentedBar(
                    prefix: 'shift-fit-${s.shiftId}',
                    selected: review?.shiftFit,
                    onPick: (fit) => _saveShiftFit(s, review, fit),
                  ),
                  if (showReason) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Possible context: ${s.proposedContext}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Did this context play a part?',
                      style: TextStyle(fontSize: 11.5, color: _soft),
                    ),
                    const SizedBox(height: 6),
                    _segmentedBar(
                      prefix: 'reason-fit-${s.shiftId}',
                      selected: review?.reasonFit,
                      onPick: (rf) => _saveReasonFit(s, review, rf),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (nextPending != null && nextPending.shiftId != s.shiftId)
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _expandedShiftId = nextPending.shiftId,
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                          label: const Text(
                            'Next shift',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: () =>
                              setState(() => _expandedShiftId = null),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
