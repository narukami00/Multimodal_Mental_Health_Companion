import '../../core/models/chat_conversation_record.dart';
import '../../core/models/session_record.dart';
import '../chat/conversation_breakdown.dart';

/// User-reported agreement / fit counts for journal emotion readings.
/// Explicit denominator: [reviewed] = [accepted] + [corrected] + [unsure].
/// [skipped] and [unanswered] are tracked separately and excluded from [fitRate].
/// These reflect personal agreement with model estimates, NOT clinical or
/// objective classifier accuracy.
class JournalReviewStats {
  const JournalReviewStats({
    required this.readingsTotal,
    required this.reviewed,
    required this.accepted,
    required this.corrected,
    required this.unsure,
    required this.skipped,
    required this.unanswered,
  });

  final int readingsTotal;
  final int reviewed;
  final int accepted;
  final int corrected;
  final int unsure;
  final int skipped;
  final int unanswered;

  double? get fitRate => reviewed == 0 ? null : accepted / reviewed;
}

/// User-reported agreement counts for chat trajectory shifts and proposed
/// contextual explanations, kept strictly separate.
class TrajectoryReviewStats {
  const TrajectoryReviewStats({
    required this.shiftsTotal,
    required this.shiftReviewed,
    required this.shiftAgreed,
    required this.shiftDisagreed,
    required this.shiftUnsure,
    required this.shiftSkipped,
    required this.shiftUnanswered,
    required this.reasonProposedTotal,
    required this.reasonReviewed,
    required this.reasonAgreed,
    required this.reasonDisagreed,
    required this.reasonUnsure,
    required this.reasonSkipped,
    required this.reasonUnanswered,
  });

  final int shiftsTotal;
  final int shiftReviewed;
  final int shiftAgreed;
  final int shiftDisagreed;
  final int shiftUnsure;
  final int shiftSkipped;
  final int shiftUnanswered;

  final int reasonProposedTotal;
  final int reasonReviewed;
  final int reasonAgreed;
  final int reasonDisagreed;
  final int reasonUnsure;
  final int reasonSkipped;
  final int reasonUnanswered;

  double? get shiftFitRate =>
      shiftReviewed == 0 ? null : shiftAgreed / shiftReviewed;
  double? get reasonFitRate =>
      reasonReviewed == 0 ? null : reasonAgreed / reasonReviewed;
}

class ReviewStatistics {
  const ReviewStatistics({
    required this.journal,
    required this.trajectory,
  });

  final JournalReviewStats journal;
  final TrajectoryReviewStats trajectory;

  static ReviewStatistics compute({
    required List<SessionRecord> sessions,
    required List<ChatConversationRecord> conversations,
  }) {
    var readingsTotal = 0;
    var accepted = 0;
    var corrected = 0;
    var unsure = 0;
    var skipped = 0;

    for (final s in sessions) {
      if (s.reading == null) continue;
      readingsTotal++;
      final review = s.moodReview;
      if (review == null) continue;
      if (review.status == MoodReviewStatus.corrected) {
        corrected++;
      } else if (review.status == MoodReviewStatus.noneFits) {
        unsure++;
      } else if (review.matchesReading(s.reading)) {
        if (review.status == MoodReviewStatus.accepted) {
          accepted++;
        } else if (review.status == MoodReviewStatus.skipped) {
          skipped++;
        }
      }
    }
    final jReviewed = accepted + corrected + unsure;
    final jUnanswered = (readingsTotal - jReviewed - skipped).clamp(0, readingsTotal);

    var shiftsTotal = 0;
    var shiftAgreed = 0;
    var shiftDisagreed = 0;
    var shiftUnsure = 0;
    var shiftSkipped = 0;

    var reasonProposedTotal = 0;
    var reasonAgreed = 0;
    var reasonDisagreed = 0;
    var reasonUnsure = 0;
    var reasonSkipped = 0;

    for (final conv in conversations) {
      final breakdown = ConversationBreakdown.from(conv);
      final byShiftId = <String, TrajectoryShiftReview>{
        for (final r in conv.shiftReviews) r.shiftId: r,
      };
      for (final shift in breakdown.shifts) {
        shiftsTotal++;
        if (shift.proposedContext != null) {
          reasonProposedTotal++;
        }
        final rev = byShiftId[shift.shiftId];
        if (rev == null || rev.evidenceVersion != shift.evidenceVersion) {
          continue;
        }
        switch (rev.shiftFit) {
          case ShiftAgreement.agrees:
            shiftAgreed++;
          case ShiftAgreement.disagrees:
            shiftDisagreed++;
          case ShiftAgreement.unsure:
            shiftUnsure++;
          case ShiftAgreement.skipped:
            shiftSkipped++;
        }
        if (shift.proposedContext != null && rev.reasonFit != null) {
          switch (rev.reasonFit!) {
            case ShiftAgreement.agrees:
              reasonAgreed++;
            case ShiftAgreement.disagrees:
              reasonDisagreed++;
            case ShiftAgreement.unsure:
              reasonUnsure++;
            case ShiftAgreement.skipped:
              reasonSkipped++;
          }
        }
      }
    }

    final shiftReviewed = shiftAgreed + shiftDisagreed + shiftUnsure;
    final shiftUnanswered =
        (shiftsTotal - shiftReviewed - shiftSkipped).clamp(0, shiftsTotal);
    final reasonReviewed = reasonAgreed + reasonDisagreed + reasonUnsure;
    final reasonUnanswered =
        (reasonProposedTotal - reasonReviewed - reasonSkipped).clamp(0, reasonProposedTotal);

    return ReviewStatistics(
      journal: JournalReviewStats(
        readingsTotal: readingsTotal,
        reviewed: jReviewed,
        accepted: accepted,
        corrected: corrected,
        unsure: unsure,
        skipped: skipped,
        unanswered: jUnanswered,
      ),
      trajectory: TrajectoryReviewStats(
        shiftsTotal: shiftsTotal,
        shiftReviewed: shiftReviewed,
        shiftAgreed: shiftAgreed,
        shiftDisagreed: shiftDisagreed,
        shiftUnsure: shiftUnsure,
        shiftSkipped: shiftSkipped,
        shiftUnanswered: shiftUnanswered,
        reasonProposedTotal: reasonProposedTotal,
        reasonReviewed: reasonReviewed,
        reasonAgreed: reasonAgreed,
        reasonDisagreed: reasonDisagreed,
        reasonUnsure: reasonUnsure,
        reasonSkipped: reasonSkipped,
        reasonUnanswered: reasonUnanswered,
      ),
    );
  }
}
