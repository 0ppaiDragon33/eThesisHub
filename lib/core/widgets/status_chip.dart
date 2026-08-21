import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

/// Where a thesis currently sits, named by the desk it is sitting on.
///
/// This is the one piece of vocabulary the whole system shares — it appears
/// on the student's status screen, in the coordinator's and dean's queues,
/// and beside each thesis in a list. Everywhere it appears it must say the
/// same thing, which is why the wording and colour live here and not in each
/// screen.
///
/// The labels name an office rather than a state ("With the Dean", not
/// "nominationPendingDean") because that is how the people using this
/// describe it: the paper is with someone. A student who asks their
/// groupmate where the form is gets that answer, not a status code.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});

  final ThesisStatus status;

  /// Tighter, for use inside a dense list row.
  final bool dense;

  static String labelFor(ThesisStatus status) => switch (status) {
        ThesisStatus.draft => 'Draft',
        ThesisStatus.nominationPendingConforme => 'Awaiting Conforme',
        ThesisStatus.nominationPendingCoordinator => 'With the Coordinator',
        ThesisStatus.nominationPendingDean => 'With the Dean',
        ThesisStatus.nominationApproved => 'Approved',
        ThesisStatus.titlePendingDefence => 'Title defence',
        ThesisStatus.titleApproved => 'Title approved',
        ThesisStatus.titleRejected => 'Titles returned',
      };

  /// One sentence saying what happens next, for the screens that have room.
  /// Empty for the two states that need no explanation.
  static String detailFor(ThesisStatus status) => switch (status) {
        ThesisStatus.draft =>
          'Nominate an adviser and panel to submit this group.',
        ThesisStatus.nominationPendingConforme =>
          'Each nominee is being asked to accept.',
        ThesisStatus.nominationPendingCoordinator =>
          'The College Research Coordinator is reviewing the nomination.',
        ThesisStatus.nominationPendingDean =>
          'The Dean is reviewing the nomination.',
        ThesisStatus.nominationApproved =>
          'Form 1 is ready to download.',
        ThesisStatus.titlePendingDefence =>
          'Your candidate titles are with the panel.',
        ThesisStatus.titleApproved =>
          'Your title is approved. Work begins on the chapters.',
        ThesisStatus.titleRejected =>
          'The panel returned your candidates. Read the remark and submit a '
          'new set.',
      };

  static Color _colorFor(ThesisStatus status, Brightness brightness) {
    final light = brightness == Brightness.light;
    return switch (status) {
      // Draft is the only state that is nobody's responsibility yet, so it
      // is the only one drawn in plain ink.
      ThesisStatus.draft =>
        light ? AppTokens.inkMuted : AppTokens.inkMutedDark,
      ThesisStatus.nominationPendingConforme ||
      ThesisStatus.nominationPendingCoordinator ||
      ThesisStatus.nominationPendingDean ||
      ThesisStatus.titlePendingDefence =>
        light ? AppTokens.awaiting : AppTokens.awaitingDark,
      ThesisStatus.nominationApproved || ThesisStatus.titleApproved =>
        light ? AppTokens.endorsed : AppTokens.endorsedDark,
      ThesisStatus.titleRejected =>
        light ? AppTokens.returned : AppTokens.returnedDark,
    };
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = _colorFor(status, brightness);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppTokens.sm : AppTokens.md - AppTokens.xs,
        vertical: dense ? 2 : AppTokens.xs + 1,
      ),
      decoration: BoxDecoration(
        // A tinted field with a matching hairline, not a solid fill: a
        // status here is an annotation on a document, and a saturated block
        // of colour would outweigh the thesis title it sits beside.
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        labelFor(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// The single vocabulary for chapter states, alongside [StatusChip]'s
/// thesis vocabulary. Kept here so the words a student reads are decided
/// in one place rather than per screen.
class ChapterStatusWords {
  static String labelFor(ChapterStatus status) => switch (status) {
        ChapterStatus.submitted => 'With your adviser',
        ChapterStatus.revise => 'Needs revision',
        ChapterStatus.approved => 'Approved',
      };

  static String detailFor(ChapterStatus status) => switch (status) {
        ChapterStatus.submitted =>
          'Your adviser has this version and has not responded yet.',
        ChapterStatus.revise =>
          'Read the feedback, then upload the next version.',
        ChapterStatus.approved =>
          'Locked. Only your adviser can reopen it.',
      };
}
