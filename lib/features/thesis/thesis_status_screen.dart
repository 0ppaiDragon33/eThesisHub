import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/form1_data.dart';
import 'package:ethesishub/features/forms/form1_pdf.dart';
import 'package:ethesishub/features/titles/consolidated_comments.dart';
import 'package:ethesishub/providers/auth_providers.dart';
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

    return Scaffold(
      key: const Key('thesisStatusScreen'),
      appBar: AppBar(title: const Text('My thesis')),
      body: thesisAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load your thesis.')),
        data: (thesis) {
          if (thesis == null) {
            return const Center(
                child: Text('You have not created a thesis group yet.'));
          }
          return StreamBuilder<List<Nomination>>(
            stream: ref
                .read(thesisRepositoryProvider)
                .watchNominations(thesis.id),
            builder: (context, snap) {
              final nominations = snap.data ?? const <Nomination>[];
              final anyDeclined = nominations
                  .any((n) => n.conformeStatus == ConformeStatus.declined);
              final stalledByDecline =
                  thesis.status == ThesisStatus.nominationPendingConforme &&
                      anyDeclined;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(thesis.workingTitle,
                      key: const Key('workingTitle'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(label(thesis.status), key: const Key('statusLabel')),
                  const SizedBox(height: 16),
                  if (nominations.isNotEmpty)
                    Text('Panel',
                        style: Theme.of(context).textTheme.titleMedium),
                  for (final n in nominations)
                    ListTile(
                      dense: true,
                      title: Text(n.nomineeName),
                      subtitle: Text(n.exOfficio
                          ? '${n.position.value} · ex officio'
                          : n.position.value),
                      trailing: Text(
                        key: Key('conforme-${n.nomineeUid}'),
                        switch (n.conformeStatus) {
                          ConformeStatus.accepted => 'Accepted',
                          ConformeStatus.declined =>
                            'Declined — ${n.declineReason ?? ''}',
                          ConformeStatus.exOfficio => 'Ex officio',
                          ConformeStatus.pending => 'Pending',
                        },
                      ),
                    ),
                  if (stalledByDecline)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'One or more nominees declined, and this thesis '
                        'cannot be re-nominated from here. Please contact '
                        'your Research Coordinator so they can reopen this '
                        'thesis for re-nomination.',
                        key: const Key('reNominationGap'),
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  // The student cannot fix what they cannot read, so the
                  // remark comes before the resubmit action below.
                  if (thesis.status == ThesisStatus.titleRejected &&
                      (thesis.titleRejectionRemark ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ErrorState(
                        message: 'This set was rejected: '
                            '${thesis.titleRejectionRemark}',
                      ),
                    ),
                  // The single decision this whole milestone exists to
                  // record was invisible to the group it was made about:
                  // `approvedTitleId` was written and rendered nowhere, so an
                  // approved thesis showed a generic chip and the comment
                  // blocks for every candidate, with no mark on the winner.
                  if (thesis.status == ThesisStatus.titleApproved &&
                      thesis.approvedTitleId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _ApprovedTitle(
                        thesisId: thesis.id,
                        approvedTitleId: thesis.approvedTitleId!,
                      ),
                    ),
                  if (thesis.titleDecidedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: _ConsolidatedComments(
                        thesisId: thesis.id,
                        round: thesis.titleRound,
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (thesis.status == ThesisStatus.draft)
                    FilledButton.icon(
                      key: const Key('nominateAction'),
                      icon: const Icon(Icons.how_to_reg),
                      label: const Text('Nominate adviser and panel'),
                      onPressed: () =>
                          context.go('/thesis/nominate?id=${thesis.id}'),
                    ),
                  if (thesis.status == ThesisStatus.nominationApproved)
                    FilledButton.icon(
                      key: const Key('downloadForm1'),
                      icon: const Icon(Icons.download),
                      label: const Text('Download Form 1'),
                      onPressed: () => _download(ref, thesis, nominations),
                    ),
                  if (thesis.status == ThesisStatus.nominationApproved ||
                      thesis.status == ThesisStatus.titleRejected)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.icon(
                        key: const Key('goToSubmitTitles'),
                        icon: const Icon(Icons.edit_document),
                        label: Text(thesis.status == ThesisStatus.titleRejected
                            ? 'Resubmit candidate titles'
                            : 'Submit candidate titles'),
                        onPressed: () =>
                            context.go('/thesis/titles?id=${thesis.id}'),
                      ),
                    ),
                  // The Dean's approval is the event that unlocks chapter
                  // uploads (ChaptersScreen itself refuses any status other
                  // than titleApproved), so this is the one status that
                  // gets an entry point into them from here.
                  if (thesis.status == ThesisStatus.titleApproved)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.icon(
                        key: const Key('goToChapters'),
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('Go to chapters'),
                        onPressed: () =>
                            context.go('/thesis/chapters?id=${thesis.id}'),
                      ),
                    ),
                ],
              );
            },
          );
        },
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

    return Container(
      key: const Key('approvedTitle'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 20),
              const SizedBox(width: 8),
              Text('Approved title',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            approved ?? 'The approved title could not be found.',
            key: const Key('approvedTitleText'),
            style: Theme.of(context).textTheme.titleMedium,
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
  const _ConsolidatedComments({required this.thesisId, required this.round});

  final String thesisId;
  final int round;

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

    return Column(
      key: const Key('consolidatedComments'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Panel comments',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final candidate in consolidated)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.candidate.titleText,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final block in candidate.blocks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(block.header,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        for (final body in block.bodies)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, top: 2),
                            child: Text(body),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
