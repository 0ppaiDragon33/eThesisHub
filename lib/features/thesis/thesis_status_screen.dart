import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/form1_data.dart';
import 'package:ethesishub/features/forms/form1_pdf.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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

  static String label(ThesisStatus s) => switch (s) {
        ThesisStatus.draft => 'Draft — nominate your adviser and panel',
        ThesisStatus.nominationPendingConforme =>
          'Waiting for nominees to accept',
        ThesisStatus.nominationPendingCoordinator =>
          'Waiting for the Research Coordinator',
        ThesisStatus.nominationPendingDean => 'Waiting for the Dean',
        ThesisStatus.nominationApproved => 'Nomination approved',
      };

  Future<void> _download(
      WidgetRef ref, Thesis thesis, List<Nomination> nominations) async {
    final leader =
        await ref.read(userRepositoryProvider).fetchUser(thesis.leaderUid);
    final data = Form1Data.assemble(
      thesis: thesis,
      nominations: nominations,
      leaderName: leader?.fullName ?? '',
      directoryNames: const {},
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
                ],
              );
            },
          );
        },
      ),
    );
  }
}
