import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
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
        ThesisStatus.archived => 'Archived',
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
        ThesisStatus.archived => 'Your thesis manuscript is published in the '
          'college archive.',
      };

  /// The meaning of a status, in the shared [Tone] vocabulary.
  static Tone toneFor(ThesisStatus status) => switch (status) {
        // Draft is the only state that is nobody's responsibility yet.
        ThesisStatus.draft => Tone.neutral,
        ThesisStatus.nominationPendingConforme ||
        ThesisStatus.nominationPendingCoordinator ||
        ThesisStatus.nominationPendingDean ||
        ThesisStatus.titlePendingDefence =>
          Tone.awaiting,
        ThesisStatus.nominationApproved ||
        ThesisStatus.titleApproved ||
        ThesisStatus.archived =>
          Tone.endorsed,
        ThesisStatus.titleRejected => Tone.returned,
      };

  /// A glyph per status, so the word is never the only carrier besides
  /// colour.
  static IconData iconFor(ThesisStatus status) => switch (status) {
        ThesisStatus.draft => Icons.edit_note_rounded,
        ThesisStatus.nominationPendingConforme =>
          Icons.how_to_reg_outlined,
        ThesisStatus.nominationPendingCoordinator =>
          Icons.inventory_2_outlined,
        ThesisStatus.nominationPendingDean => Icons.gavel_outlined,
        ThesisStatus.nominationApproved => Icons.verified_outlined,
        ThesisStatus.titlePendingDefence => Icons.forum_outlined,
        ThesisStatus.titleApproved => Icons.task_alt_rounded,
        ThesisStatus.titleRejected => Icons.undo_rounded,
        ThesisStatus.archived => Icons.local_library_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return ToneBadge(
      label: labelFor(status),
      tone: toneFor(status),
      icon: iconFor(status),
      dense: dense,
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

  static Tone toneFor(ChapterStatus status) => switch (status) {
        ChapterStatus.submitted => Tone.awaiting,
        ChapterStatus.revise => Tone.returned,
        ChapterStatus.approved => Tone.endorsed,
      };

  static IconData iconFor(ChapterStatus status) => switch (status) {
        ChapterStatus.submitted => Icons.schedule_outlined,
        ChapterStatus.revise => Icons.undo_rounded,
        ChapterStatus.approved => Icons.lock_outline_rounded,
      };

  /// The same palette [StatusChip] uses, so a chapter waiting on someone
  /// reads as the same kind of state as a thesis waiting on someone.
  static Color colorFor(ChapterStatus status, Brightness brightness) {
    final light = brightness == Brightness.light;
    return switch (status) {
      ChapterStatus.submitted =>
        light ? AppTokens.awaiting : AppTokens.awaitingDark,
      ChapterStatus.revise =>
        light ? AppTokens.returned : AppTokens.returnedDark,
      ChapterStatus.approved =>
        light ? AppTokens.endorsed : AppTokens.endorsedDark,
    };
  }
}
