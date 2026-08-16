import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Lets a faculty member give (or withhold) their Conforme on nominations
/// addressed to them. `watchMyPendingNominations` already excludes ex
/// officio seats — the dean and every research coordinator sit on each
/// panel automatically and are never asked to accept
/// (`Nomination.needsConforme => !exOfficio`, filtered at the query level
/// via `conformeStatus == pending`, which an ex-officio seat never is; its
/// status is always `exOfficio`). The same person may still legitimately
/// appear here for a *different* nomination if they were nominated by name
/// as adviser or panelist "for the sake of records" — that nomination is
/// not ex officio and does require their acceptance.
///
/// `respondToNomination` throws `StateError` when the thesis has already
/// left `nominationPendingConforme` by the time this screen's write lands
/// (e.g. a stale tab: the last co-nominee's accept already advanced the
/// thesis while this tab sat open). That is surfaced as a plain human
/// message here, not a raw error, and busy state is cleared on every path
/// so the button is left tappable again afterward.
///
/// Reached from the faculty dashboard's "Nomination inbox" button, at
/// `/nominations`.
class NominationInboxScreen extends ConsumerStatefulWidget {
  const NominationInboxScreen({super.key});

  @override
  ConsumerState<NominationInboxScreen> createState() =>
      _NominationInboxScreenState();
}

class _NominationInboxScreenState
    extends ConsumerState<NominationInboxScreen> {
  final _reason = TextEditingController();
  String? _decliningThesisId;
  String? _error;
  final Set<String> _busy = {};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _respond(String uid, String thesisId, bool accept) async {
    if (_busy.contains(thesisId)) return; // guards against a double tap

    if (!accept && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Please give a reason for declining.');
      return;
    }

    setState(() {
      _busy.add(thesisId);
      _error = null;
    });

    try {
      await ref.read(thesisRepositoryProvider).respondToNomination(
            thesisId: thesisId,
            nomineeUid: uid,
            accept: accept,
            declineReason: accept ? null : _reason.text.trim(),
          );
      if (mounted) {
        setState(() {
          _decliningThesisId = null;
          _reason.clear();
        });
      }
    } on StateError catch (_) {
      // Reachable in normal use, not just theoretically: a nominee leaves
      // the inbox open, the last co-nominee accepts (advancing the
      // thesis), then the stale tab taps Accept/Decline.
      if (mounted) {
        setState(
            () => _error = 'This nomination has already been completed.');
      }
    } on FirebaseException catch (_) {
      // Checked before the catch-all: FirebaseAuthException is itself a
      // subtype of FirebaseException, so a specific-to-general catch order
      // matters even though this call never touches auth.
      if (mounted) setState(() => _error = 'Could not record your response.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record your response.');
    } finally {
      if (mounted) setState(() => _busy.remove(thesisId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read lazily inside the submit handler — see
    // nominate_screen.dart / create_thesis_screen.dart for the race this
    // avoids: reading it for the first time inside a tap handler can see a
    // stale null before the auth stream's first event has landed.
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final pending = ref.watch(myPendingNominationsProvider);

    return Scaffold(
      key: const Key('nominationInboxScreen'),
      appBar: AppBar(title: const Text('Nomination inbox')),
      body: pending.when(
        loading: () => const LoadingState(label: 'Loading your nominations…'),
        // The error object is passed through rather than discarded: there
        // are no server-side logs on Spark, so the code shown beside this
        // message is the only way to tell a missing index from a rules
        // refusal without attaching a debugger.
        error: (e, _) => PageShell(children: [
          ErrorState(error: e, message: 'Could not load your nominations.'),
        ]),
        data: (items) {
          if (items.isEmpty) {
            return const PageShell(children: [
              EmptyState(
                icon: Icons.drafts_outlined,
                title: 'No nominations waiting',
                message: 'When a group nominates you as their adviser or a '
                    'panel member, the request appears here.',
              ),
            ]);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      key: const Key('error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              for (final item in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ThesisTitle(thesisId: item.thesisId),
                        Text('Nominated as ${item.nomination.position.value}'),
                        if (_decliningThesisId == item.thesisId) ...[
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('declineReason'),
                            controller: _reason,
                            decoration: const InputDecoration(
                                labelText: 'Reason for declining'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton(
                              key: Key('accept-${item.thesisId}'),
                              onPressed: (uid == null ||
                                      _busy.contains(item.thesisId))
                                  ? null
                                  : () => _respond(uid, item.thesisId, true),
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 10),
                            if (_decliningThesisId == item.thesisId)
                              OutlinedButton(
                                key: const Key('confirmDecline'),
                                onPressed: (uid == null ||
                                        _busy.contains(item.thesisId))
                                    ? null
                                    : () =>
                                        _respond(uid, item.thesisId, false),
                                child: const Text('Confirm decline'),
                              )
                            else
                              OutlinedButton(
                                key: Key('decline-${item.thesisId}'),
                                onPressed: _busy.contains(item.thesisId)
                                    ? null
                                    : () => setState(() {
                                          _decliningThesisId = item.thesisId;
                                          _error = null;
                                        }),
                                child: const Text('Decline'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ThesisTitle extends ConsumerWidget {
  const _ThesisTitle({required this.thesisId});

  final String thesisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesis =
        ref.watch(thesisRepositoryProvider).watchThesis(thesisId);
    return StreamBuilder(
      stream: thesis,
      builder: (context, snap) => Text(
        snap.data?.workingTitle ?? '…',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
