import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/open_document.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/progress_rail.dart';
import 'package:ethesishub/features/documents/manuscript_upload.dart';
import 'package:ethesishub/features/forms/form1_data.dart';
import 'package:ethesishub/features/forms/form1_pdf.dart';
import 'package:ethesishub/features/titles/consolidated_comments.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// Shows the student leader where their thesis nomination stands: the
/// current stage, each nominee's Conforme state, and — once approved — a
/// Form 1 download. Saving/sharing goes through the `printing` package
/// rather than `dart:io`, which this app never imports anywhere: the app
/// targets both Android and Web, and `dart:io` is unavailable on Web.
///
/// Re-nomination gap: a decline is surfaced here with its reason, but no
/// "re-nominate" action is offered. `submitNominations`'s batch create (and
/// the leader's own nomination `delete`) are only permitted by
/// `firestore.rules` while the thesis is `draft`
/// (`mayCreateNomination()`/the `nominations/{nomineeUid}` delete rule both
/// require `thesisData(thesisId).status == 'draft'`), and there is no rule
/// branch that lets the leader move the thesis document itself back from
/// `nominationPendingConforme` to `draft` — the leader's `update` branch on
/// `theses/{thesisId}` only permits the single forward step `draft ->
/// nominationPendingConforme`, gated on the *current* status already being
/// `draft`. Reopening that transition safely needs its own guard (an audit
/// record, a status the leader cannot reach unilaterally, or coordinator
/// involvement) — the rules file's own comment on the nominations `delete`
/// rule warns against solving this by simply dropping the `draft` pin that
/// closed the decline-laundering hole, and that is exactly what an
/// unguarded revert-to-draft would do. Shipping a "re-nominate" button under
/// the deployed rules would therefore fail with `permission-denied` for
/// every real user; instead the screen tells the leader to contact their
/// Research Coordinator. See the task-14/15 report for the full writeup.
class ThesisStatusScreen extends ConsumerWidget {
  const ThesisStatusScreen({super.key});

  /// Delegates to [StatusChip], the single shared status vocabulary — a
  /// second switch here previously drifted from it ("Waiting for the Dean"
  /// against "With the Dean", "Nomination approved" against "Approved").
  static String label(ThesisStatus s) => StatusChip.labelFor(s);

  Future<void> _download(
      WidgetRef ref, Thesis thesis, List<Nomination> nominations) async {
    final leader =
        await ref.read(userRepositoryProvider).fetchUser(thesis.leaderUid);

    // Form 1 is printed and handed to the Dean, so the two signatory names on
    // it must not come out blank.
    //
    // `Form1Data._nameFor` falls back to the thesis's own ex-officio
    // nominations, and usually that is enough — every coordinator and the dean
    // holding a directory entry at submission time gets an ex-officio seat on
    // the thesis. But the fallback is not sufficient in the real cases the
    // fallback exists for: a coordinator promoted AFTER this thesis's
    // nominations went out has no seat on it and would print blank, as would
    // one who had not yet signed in (and so had no directory entry) when the
    // roster was fixed. The roster cannot be amended afterwards — creates are
    // pinned to `draft` — so nothing recovers the name later.
    //
    // This was passed `const {}`, which made the directory branch dead and
    // left both names resting entirely on that fallback. Resolving the two
    // uids against the live directory here is one read each, only on the
    // download path, and `facultyDirectory` is readable by any verified user.
    final directory = ref.read(facultyDirectoryRepositoryProvider);
    final directoryNames = <String, String>{};
    for (final uid in <String?>{
      thesis.coordinatorRecommendedBy,
      thesis.deanApprovedBy,
    }) {
      if (uid == null) continue;
      final entry = await directory.fetch(uid);
      if (entry != null) directoryNames[uid] = entry.fullName;
    }

    final data = Form1Data.assemble(
      thesis: thesis,
      nominations: nominations,
      leaderName: leader?.fullName ?? '',
      directoryNames: directoryNames,
    );
    final bytes = await buildForm1Pdf(data);
    await Printing.sharePdf(bytes: bytes, filename: 'Form1-${thesis.id}.pdf');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesisAsync = ref.watch(myThesisProvider);

    return KeyedSubtree(
      key: const Key('thesisStatusScreen'),
      child: thesisAsync.when(
        loading: () => const PageShell(
          maxWidth: AppTokens.measureWide,
          children: [LoadingState.page(label: 'Loading your thesis…')],
        ),
        error: (e, _) => PageShell(children: [
          ErrorState(
            error: e,
            message: 'Could not load your thesis.',
            onRetry: () => ref.invalidate(myThesisProvider),
          ),
        ]),
        data: (thesis) {
          if (thesis == null) {
            // The in-app door to '/thesis/create' lives here, on the
            // destination a student without a group reaches first.
            return PageShell(
              title: 'My thesis',
              subtitle: 'Your group\'s workspace appears here once it '
                  'exists.',
              children: [
                EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No thesis group yet',
                  message: 'Create your group to name your working title and '
                      'list your members. You will nominate an adviser and '
                      'panel next.',
                  action: FilledButton(
                    key: const Key('goToCreateThesis'),
                    onPressed: () => context.go('/thesis/create'),
                    child: const Text('Create thesis group'),
                  ),
                ),
              ],
            );
          }
          return StreamBuilder<List<Nomination>>(
            stream: ref
                .read(thesisRepositoryProvider)
                .watchNominations(thesis.id),
            builder: (context, snap) => FadeIn(child: _Workspace(
              thesis: thesis,
              nominations: snap.data ?? const <Nomination>[],
              nominationsLoading: !snap.hasData && !snap.hasError,
              nominationsError: snap.error,
              onDownloadForm1: () =>
                  _download(ref, thesis, snap.data ?? const []),
            )),
          );
        },
      ),
    );
  }
}

/// The thesis workspace: identity and journey across the top, the next
/// action and the decisions made so far in the main column, and the
/// people, the record and the documents beside them.
class _Workspace extends ConsumerWidget {
  const _Workspace({
    required this.thesis,
    required this.nominations,
    required this.nominationsLoading,
    required this.nominationsError,
    required this.onDownloadForm1,
  });

  final Thesis thesis;
  final List<Nomination> nominations;
  final bool nominationsLoading;
  final Object? nominationsError;
  final Future<void> Function() onDownloadForm1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final defences = ref.watch(myDefencesProvider).valueOrNull ?? const [];
    final chapters =
        ref.watch(chaptersProvider(thesis.id)).valueOrNull ?? const [];

    return PageShell(
      maxWidth: AppTokens.measureWide,
      children: [
        // Identity.
        Wrap(
          spacing: AppTokens.sm,
          runSpacing: AppTokens.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ToneBadge(
              label: ThesisStatusScreen.label(thesis.status),
              tone: StatusChip.toneFor(thesis.status),
              icon: StatusChip.iconFor(thesis.status),
              textKey: const Key('statusLabel'),
            ),
            Text(
              [thesis.college, thesis.program]
                  .where((s) => s.isNotEmpty)
                  .join(', '),
              style: text.bodySmall,
            ),
          ],
        ),
        const Gap.sm(),
        Text(
          thesis.workingTitle,
          key: const Key('workingTitle'),
          style: Breakpoint.of(context) == Breakpoint.compact
              ? text.headlineSmall
              : text.headlineMedium,
        ),
        const Gap.sm(),
        Text(
          thesis.memberNames.isEmpty
              ? 'No members listed'
              : thesis.memberNames.join(', '),
          style: text.bodyMedium?.copyWith(color: p.muted),
        ),
        const Gap.lg(),
        Panel(
          title: 'Where your thesis is',
          icon: Icons.route_outlined,
          child: ProgressRail(
            status: thesis.status,
            defences: defences,
            chapters: chapters,
          ),
        ),
        const Gap.lg(),
        SplitColumns(
          primary: [
            _NextAction(thesis: thesis, nominations: nominations,
                onDownloadForm1: onDownloadForm1),
            if (thesis.status == ThesisStatus.titleApproved &&
                thesis.approvedTitleId != null)
              _ApprovedTitle(
                thesisId: thesis.id,
                approvedTitleId: thesis.approvedTitleId!,
              ),
            if (thesis.titleDecidedAt != null)
              Panel(
                title: 'Panel comments',
                subtitle: 'Round ${thesis.titleRound}, grouped by candidate and '
                    'panel member',
                icon: Icons.forum_outlined,
                child: _ConsolidatedComments(
                  thesisId: thesis.id,
                  round: thesis.titleRound,
                  approvedTitleId: thesis.approvedTitleId,
                ),
              ),
            // Decides its own visibility from the final defence verdict;
            // renders nothing until that verdict is a pass.
            ManuscriptUpload(thesis: thesis),
            _History(thesis: thesis),
          ],
          secondary: [
            _PeoplePanel(
              nominations: nominations,
              loading: nominationsLoading,
              error: nominationsError,
            ),
            _DocumentsPanel(thesis: thesis, onDownloadForm1: onDownloadForm1),
            Panel(
              title: 'Record',
              icon: Icons.info_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FactLine(label: 'College', value: thesis.college),
                  FactLine(label: 'Program', value: thesis.program),
                  FactLine(
                    label: 'Term',
                    value: [thesis.semester, thesis.academicYear]
                        .where((s) => s.isNotEmpty)
                        .join(', '),
                  ),
                  FactLine(
                      label: 'Group created',
                      value: Dates.day(thesis.createdAt)),
                  if (thesis.titleRound > 0)
                    FactLine(
                        label: 'Title round',
                        value: '${thesis.titleRound}'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the group does next, with the buttons that do it.
class _NextAction extends StatelessWidget {
  const _NextAction({
    required this.thesis,
    required this.nominations,
    required this.onDownloadForm1,
  });

  final Thesis thesis;
  final List<Nomination> nominations;
  final Future<void> Function() onDownloadForm1;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final anyDeclined =
        nominations.any((n) => n.conformeStatus == ConformeStatus.declined);
    final stalledByDecline =
        thesis.status == ThesisStatus.nominationPendingConforme && anyDeclined;

    final actions = <Widget>[
      if (thesis.status == ThesisStatus.draft)
        FilledButton.icon(
          key: const Key('nominateAction'),
          icon: const Icon(Icons.how_to_reg, size: 18),
          label: const Text('Nominate adviser and panel'),
          onPressed: () => context.go('/thesis/nominate?id=${thesis.id}'),
        ),
      if (thesis.status == ThesisStatus.nominationApproved ||
          thesis.status == ThesisStatus.titleRejected)
        FilledButton.icon(
          key: const Key('goToSubmitTitles'),
          icon: const Icon(Icons.edit_document, size: 18),
          label: Text(thesis.status == ThesisStatus.titleRejected
              ? 'Resubmit candidate titles'
              : 'Submit candidate titles'),
          onPressed: () => context.go('/thesis/titles?id=${thesis.id}'),
        ),
      if (thesis.status == ThesisStatus.nominationApproved)
        OutlinedButton.icon(
          key: const Key('downloadForm1'),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Download Form 1'),
          onPressed: onDownloadForm1,
        ),
      // The Dean's title approval unlocks chapter uploads.
      if (thesis.status == ThesisStatus.titleApproved)
        FilledButton.icon(
          key: const Key('goToChapters'),
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: const Text('Go to chapters'),
          onPressed: () => context.go('/thesis/chapters?id=${thesis.id}'),
        ),
    ];

    return Panel(
      title: 'Next',
      icon: Icons.flag_outlined,
      emphasis: actions.isNotEmpty || stalledByDecline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(StatusChip.detailFor(thesis.status), style: text.bodyLarge),
          if (stalledByDecline) ...[
            const Gap.md(),
            // No re-nominate button: the rules only let the Coordinator
            // reopen a thesis (see the class note on ThesisStatusScreen).
            ErrorState(
              key: const Key('reNominationGap'),
              message: 'One or more nominees declined, and this thesis '
                  'cannot be re-nominated from here. Please contact your '
                  'Research Coordinator so they can reopen this thesis for '
                  're-nomination.',
            ),
          ],
          // The student cannot fix what they cannot read, so the remark
          // comes before the resubmit action.
          if (thesis.status == ThesisStatus.titleRejected &&
              (thesis.titleRejectionRemark ?? '').isNotEmpty) ...[
            const Gap.md(),
            ErrorState(
              message: 'This set was rejected: '
                  '${thesis.titleRejectionRemark}',
            ),
          ],
          if (actions.isNotEmpty) ...[
            const Gap.md(),
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              children: actions,
            ),
          ] else if (!stalledByDecline) ...[
            const Gap.sm(),
            Text('Nothing for your group to do right now.',
                style: text.bodySmall?.copyWith(color: p.muted)),
          ],
        ],
      ),
    );
  }
}

/// Every nominee and where their acceptance stands.
class _PeoplePanel extends StatelessWidget {
  const _PeoplePanel({
    required this.nominations,
    required this.loading,
    required this.error,
  });

  final List<Nomination> nominations;
  final bool loading;
  final Object? error;

  static String positionLabel(NominationPosition p) => switch (p) {
        NominationPosition.adviser => 'Adviser',
        NominationPosition.panelist => 'Panel member',
        NominationPosition.coordinator => 'Research Coordinator',
        NominationPosition.dean => 'Dean',
      };

  @override
  Widget build(BuildContext context) {
    final sorted = [...nominations]
      ..sort((a, b) => a.position.index.compareTo(b.position.index));
    return Panel(
      title: 'Adviser and panel',
      icon: Icons.groups_outlined,
      child: loading
          ? const LoadingState()
          : error != null
              ? ErrorState(error: error, message: 'Could not load nominees.')
              : sorted.isEmpty
                  ? Text(
                      'No one nominated yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : Column(
                      children: [
                        for (final n in sorted)
                          PersonLine(
                            name: n.nomineeName,
                            role: n.exOfficio
                                ? '${positionLabel(n.position)}, ex officio'
                                : positionLabel(n.position),
                            trailing: _ConformeBadge(n: n),
                          ),
                      ],
                    ),
    );
  }
}

class _ConformeBadge extends StatelessWidget {
  const _ConformeBadge({required this.n});

  final Nomination n;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (n.conformeStatus) {
      ConformeStatus.accepted => ('Accepted', Tone.endorsed),
      ConformeStatus.declined => ('Declined', Tone.returned),
      ConformeStatus.exOfficio => ('Ex officio', Tone.neutral),
      ConformeStatus.pending => ('Pending', Tone.awaiting),
    };
    final badge = ToneBadge(
      key: Key('conforme-${n.nomineeUid}'),
      label: label,
      tone: tone,
      dense: true,
    );
    final reason = n.declineReason;
    if (n.conformeStatus != ConformeStatus.declined ||
        reason == null ||
        reason.isEmpty) {
      return badge;
    }
    return Tooltip(message: 'Reason: $reason', child: badge);
  }
}

class _DocumentsPanel extends ConsumerWidget {
  const _DocumentsPanel({required this.thesis, required this.onDownloadForm1});

  final Thesis thesis;
  final Future<void> Function() onDownloadForm1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvedOnward = thesis.deanApprovedAt != null ||
        thesis.status == ThesisStatus.nominationApproved;
    final rows = <Widget>[
      if (approvedOnward)
        _DocRow(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Form 1',
          detail: 'Nomination of adviser and panel',
          action: 'Download',
          onTap: onDownloadForm1,
        ),
      if ((thesis.presentationPath ?? '').isNotEmpty)
        _DocRow(
          icon: Icons.slideshow_outlined,
          title: 'Title defence presentation',
          detail: 'Submitted with your candidate titles',
          action: 'Open',
          onTap: () => openStoredDocument(context, ref, thesis.presentationPath!,
              label: 'the title defence presentation'),
        ),
      if (thesis.hasManuscript)
        _DocRow(
          icon: Icons.menu_book_outlined,
          title: 'Final manuscript',
          detail: thesis.manuscriptUploadedAt == null
              ? 'Submitted'
              : 'Submitted ${Dates.day(thesis.manuscriptUploadedAt!)}',
          action: 'Open',
          onTap: () => openStoredDocument(context, ref, thesis.manuscriptPath!,
              label: 'the final manuscript'),
        ),
    ];
    return Panel(
      title: 'Documents',
      icon: Icons.folder_open_outlined,
      flush: rows.isNotEmpty,
      trailing: TextButton(
        onPressed: () => context.go('/forms'),
        child: const Text('All forms'),
      ),
      child: rows.isEmpty
          ? Text(
              'Your forms and files appear here as each stage is completed.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Column(children: rows),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.lg - 4, AppTokens.sm + 2, AppTokens.sm, AppTokens.sm + 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.seal),
          const SizedBox(width: AppTokens.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.labelLarge),
                Text(detail, style: text.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await onTap();
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open $title.')),
                );
              }
            },
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// The decisions recorded on this thesis, oldest first, from the dates the
/// repository writes as each office acts.
class _History extends StatelessWidget {
  const _History({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context) {
    final t = thesis;
    final events = <({DateTime at, String what, Tone tone, IconData icon})>[
      (
        at: t.createdAt,
        what: 'Thesis group created',
        tone: Tone.neutral,
        icon: Icons.groups_outlined,
      ),
      if (t.nominationsSubmittedAt != null)
        (
          at: t.nominationsSubmittedAt!,
          what: 'Adviser and panel nominated',
          tone: Tone.awaiting,
          icon: Icons.how_to_reg_outlined,
        ),
      if (t.coordinatorRecommendedAt != null)
        (
          at: t.coordinatorRecommendedAt!,
          what: 'Recommended by the Research Coordinator',
          tone: Tone.endorsed,
          icon: Icons.inventory_2_outlined,
        ),
      if (t.deanApprovedAt != null)
        (
          at: t.deanApprovedAt!,
          what: 'Nomination approved by the Dean',
          tone: Tone.endorsed,
          icon: Icons.verified_outlined,
        ),
      if (t.titlesSubmittedAt != null)
        (
          at: t.titlesSubmittedAt!,
          what: t.titleRound > 1
              ? 'Candidate titles resubmitted (round ${t.titleRound})'
              : 'Candidate titles submitted',
          tone: Tone.awaiting,
          icon: Icons.edit_document,
        ),
      if (t.titleDecidedAt != null)
        (
          at: t.titleDecidedAt!,
          what: t.status == ThesisStatus.titleRejected
              ? 'Candidate titles returned'
              : 'Title approved',
          tone: t.status == ThesisStatus.titleRejected
              ? Tone.returned
              : Tone.endorsed,
          icon: t.status == ThesisStatus.titleRejected
              ? Icons.undo_rounded
              : Icons.task_alt_rounded,
        ),
      if (t.manuscriptUploadedAt != null)
        (
          at: t.manuscriptUploadedAt!,
          what: 'Final manuscript submitted',
          tone: Tone.act,
          icon: Icons.upload_file_outlined,
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));

    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    return Panel(
      title: 'History',
      subtitle: 'Decisions recorded on this thesis',
      icon: Icons.history_rounded,
      child: Column(
        key: const Key('thesisHistory'),
        children: [
          for (var i = 0; i < events.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: events[i].tone
                              .color(context)
                              .withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(events[i].icon,
                            size: 16, color: events[i].tone.color(context)),
                      ),
                      if (i < events.length - 1)
                        Expanded(child: Container(width: 1.5, color: p.rule)),
                    ],
                  ),
                  const SizedBox(width: AppTokens.md - 4),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          top: 5,
                          bottom: i < events.length - 1 ? AppTokens.md : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(events[i].what, style: text.labelLarge),
                          Text(Dates.dayTime(events[i].at),
                              style: text.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Names the title the Dean approved.
///
/// Resolved through `candidateTitlesProvider` rather than stored on the
/// thesis: `candidateTitles` are immutable once submitted, so the text the
/// student reads here is exactly the text the panel judged.
class _ApprovedTitle extends ConsumerWidget {
  const _ApprovedTitle({required this.thesisId, required this.approvedTitleId});

  final String thesisId;
  final String approvedTitleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidatesAsync = ref.watch(candidateTitlesProvider(thesisId));
    final candidates = candidatesAsync.valueOrNull;

    // Loading and "the document is gone" are kept apart, the same way every
    // other branch on this screen is: telling a student their approved title
    // no longer exists while it is still loading is the M1a bug.
    if (candidatesAsync.isLoading) {
      return const LoadingState(label: 'Loading your approved title…');
    }
    final approved = candidates
        ?.where((c) => c.id == approvedTitleId)
        .map((c) => c.titleText)
        .firstOrNull;

    final c = Tone.endorsed.color(context);
    return Panel(
      key: const Key('approvedTitle'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: c),
          const SizedBox(width: AppTokens.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Approved title',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: c)),
                const SizedBox(height: AppTokens.xs),
                Text(
                  approved ?? 'The approved title could not be found.',
                  key: const Key('approvedTitleText'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The panel's remarks, consolidated per commenter under each candidate —
/// what the student reads once the Dean has recorded a decision. Shown as a
/// separate widget because it needs its own two live streams
/// (`candidateTitlesProvider`, `titleCommentsProvider`), watched only once a
/// decision exists — most statuses never render this at all.
class _ConsolidatedComments extends ConsumerWidget {
  const _ConsolidatedComments({
    required this.thesisId,
    required this.round,
    this.approvedTitleId,
  });

  final String thesisId;
  final int round;
  final String? approvedTitleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidatesAsync = ref.watch(candidateTitlesProvider(thesisId));
    final commentsAsync = ref.watch(titleCommentsProvider(thesisId));

    if (candidatesAsync.isLoading || commentsAsync.isLoading) {
      return const LoadingState(label: 'Loading panel comments…');
    }
    if (candidatesAsync.hasError) {
      return ErrorState(
        error: candidatesAsync.error,
        message: 'Could not load the candidate titles.',
      );
    }
    if (commentsAsync.hasError) {
      return ErrorState(
        error: commentsAsync.error,
        message: 'Could not load the panel comments.',
      );
    }

    final consolidated = consolidate(
      candidates: candidatesAsync.valueOrNull ?? const [],
      comments: commentsAsync.valueOrNull ?? const [],
      round: round,
    );

    // The approved title first, then candidates with remarks, then the
    // ones nobody commented on. Numbering keeps the submitted order.
    final numbered = [
      for (var i = 0; i < consolidated.length; i++)
        (number: i + 1, item: consolidated[i]),
    ];
    int rank(ConsolidatedCandidate c) {
      if (c.candidate.id == approvedTitleId) return 0;
      return c.blocks.isEmpty ? 2 : 1;
    }
    numbered.sort((a, b) {
      final r = rank(a.item).compareTo(rank(b.item));
      return r != 0 ? r : a.number.compareTo(b.number);
    });

    final withRemarks = numbered.where((n) => n.item.blocks.isNotEmpty);
    final silent = numbered.where((n) => n.item.blocks.isEmpty).toList();

    if (numbered.isEmpty) {
      return Text('No candidate titles for this round.',
          style: Theme.of(context).textTheme.bodySmall);
    }

    return Column(
      key: const Key('consolidatedComments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in withRemarks) ...[
          _CandidateRemarks(
            number: n.number,
            candidate: n.item,
            approved: n.item.candidate.id == approvedTitleId,
          ),
          const Gap.md(),
        ],
        if (silent.isNotEmpty)
          _SilentCandidates(
            entries: silent,
            approvedTitleId: approvedTitleId,
          ),
      ],
    );
  }
}

/// One candidate and every remark on it, grouped by commenter.
class _CandidateRemarks extends StatelessWidget {
  const _CandidateRemarks({
    required this.number,
    required this.candidate,
    required this.approved,
  });

  final int number;
  final ConsolidatedCandidate candidate;
  final bool approved;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final accent = approved ? Tone.endorsed.color(context) : p.seal;
    final remarkCount =
        candidate.blocks.fold<int>(0, (a, b) => a + b.bodies.length);

    return Container(
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(
          color: approved ? accent.withValues(alpha: 0.5) : p.rule,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Candidate header.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.md, AppTokens.md, AppTokens.md, AppTokens.sm + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$number',
                      style: text.labelLarge?.copyWith(color: accent)),
                ),
                const SizedBox(width: AppTokens.md - 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(candidate.candidate.titleText,
                          style: text.titleMedium),
                      const SizedBox(height: AppTokens.xs),
                      Wrap(
                        spacing: AppTokens.sm,
                        runSpacing: AppTokens.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (approved)
                            const ToneBadge(
                              label: 'Approved title',
                              tone: Tone.endorsed,
                              icon: Icons.verified_outlined,
                              dense: true,
                            ),
                          Text(
                            remarkCount == 1
                                ? '1 remark'
                                : '$remarkCount remarks',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.rule),
          // One block per commenter.
          for (var i = 0; i < candidate.blocks.length; i++)
            Container(
              padding: const EdgeInsets.all(AppTokens.md),
              decoration: BoxDecoration(
                color: p.paper,
                border: i == candidate.blocks.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: p.rule)),
              ),
              child: _CommenterBlock(block: candidate.blocks[i]),
            ),
        ],
      ),
    );
  }
}

class _CommenterBlock extends StatelessWidget {
  const _CommenterBlock({required this.block});

  final CommentBlock block;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final sameWord = block.authorName.trim().toLowerCase() ==
        block.authorRole.trim().toLowerCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialsAvatar(block.authorName, size: 34),
        const SizedBox(width: AppTokens.md - 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppTokens.sm,
                runSpacing: AppTokens.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(block.authorName, style: text.labelLarge),
                  // "Dean, Dean" says nothing twice; show the role only
                  // when it adds something.
                  if (!sameWord && block.authorRole.isNotEmpty)
                    ToneBadge(
                      label: block.authorRole,
                      tone: Tone.neutral,
                      icon: Icons.badge_outlined,
                      dense: true,
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.sm),
              for (final body in block.bodies)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppTokens.xs + 2),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.md - 4, vertical: AppTokens.sm),
                  decoration: BoxDecoration(
                    color: p.canvas,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                      topLeft: Radius.circular(3),
                    ),
                    border: Border.all(color: p.rule),
                  ),
                  child: SelectableText(body, style: text.bodyMedium),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Candidates nobody commented on, listed compactly at the end.
class _SilentCandidates extends StatelessWidget {
  const _SilentCandidates({
    required this.entries,
    required this.approvedTitleId,
  });

  final List<({int number, ConsolidatedCandidate item})> entries;
  final String? approvedTitleId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: p.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No remarks', style: text.labelMedium),
          const SizedBox(height: AppTokens.sm),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.xs + 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text('${e.number}.',
                        style: text.labelMedium?.copyWith(color: p.muted)),
                  ),
                  Expanded(
                    child: Text(e.item.candidate.titleText,
                        style: text.bodyMedium?.copyWith(color: p.muted)),
                  ),
                  if (e.item.candidate.id == approvedTitleId)
                    const ToneBadge(
                      label: 'Approved',
                      tone: Tone.endorsed,
                      dense: true,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
