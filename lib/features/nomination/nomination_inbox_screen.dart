import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';
import 'package:ethesishub/features/nomination/change_request_inbox.dart';
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

class _NominationInboxScreenState extends ConsumerState<NominationInboxScreen> {
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
      await ref
          .read(thesisRepositoryProvider)
          .respondToNomination(
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
    } on NominationBeingRevised catch (_) {
      // The coordinator reopened this thesis for re-nomination: the request
      // here is stale and a fresh one is coming, so this is not the
      // "already completed" case — telling them that would be a lie.
      if (mounted) {
        setState(() {
          _decliningThesisId = null;
          _reason.clear();
          _error = 'The group is revising this nomination. You will get an '
              'updated request to respond to.';
        });
      }
    } on StateError catch (_) {
      // Reachable in normal use, not just theoretically: a nominee leaves
      // the inbox open, the last co-nominee accepts (advancing the
      // thesis), then the stale tab taps Accept/Decline.
      if (mounted) {
        setState(() => _error = 'This nomination has already been completed.');
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

    // No Scaffold and no AppBar: the app shell owns both for every
    // signed-in route now.
    const title = 'Nomination inbox';
    const subtitle = 'Groups asking you to serve as their adviser or on '
        'their panel. Your answer is the Conforme on their Form 1.';

    return KeyedSubtree(
      key: const Key('nominationInboxScreen'),
      child: pending.when(
        loading: () => const PageShell(
          title: title,
          subtitle: subtitle,
          children: [LoadingState(label: 'Loading your nominations…')],
        ),
        // The error object is passed through: the code shown is the only
        // way to tell a missing index from a rules refusal on Spark.
        error: (e, _) => PageShell(
          title: title,
          subtitle: subtitle,
          children: [
            ErrorState(error: e, message: 'Could not load your nominations.'),
          ],
        ),
        data: (items) => PageShell(
          title: title,
          subtitle: subtitle,
          children: [
            if (items.isEmpty)
              const EmptyState(
                icon: Icons.drafts_outlined,
                title: 'No nominations waiting',
                message: 'When a group nominates you as their adviser or a '
                    'panel member, the request appears here.',
              ),
            if (_error != null) ...[
              ErrorState(key: const Key('error'), message: _error!),
              const Gap.md(),
            ],
            for (final item in items) ...[
              _RequestCard(
                thesisId: item.thesisId,
                position: item.nomination.position,
                declining: _decliningThesisId == item.thesisId,
                busy: _busy.contains(item.thesisId),
                reason: _reason,
                onAccept: uid == null
                    ? null
                    : () => _respond(uid, item.thesisId, true),
                onStartDecline: () => setState(() {
                  _decliningThesisId = item.thesisId;
                  _error = null;
                }),
                onCancelDecline: () => setState(() {
                  _decliningThesisId = null;
                  _reason.clear();
                }),
                onConfirmDecline: uid == null
                    ? null
                    : () => _respond(uid, item.thesisId, false),
              ),
              const Gap.md(),
            ],
            const Gap.lg(),
            const ChangeRequestInbox(),
          ],
        ),
      ),
    );
  }
}

String _positionWords(NominationPosition p) => switch (p) {
      NominationPosition.adviser => 'adviser',
      NominationPosition.panelist => 'panel member',
      NominationPosition.coordinator => 'ex officio panel member',
      NominationPosition.dean => 'ex officio panel member',
    };

/// One request, read like the letter it replaces: who asks, for what, and
/// the two answers.
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.thesisId,
    required this.position,
    required this.declining,
    required this.busy,
    required this.reason,
    required this.onAccept,
    required this.onStartDecline,
    required this.onCancelDecline,
    required this.onConfirmDecline,
  });

  final String thesisId;
  final NominationPosition position;
  final bool declining;
  final bool busy;
  final TextEditingController reason;
  final VoidCallback? onAccept;
  final VoidCallback onStartDecline;
  final VoidCallback onCancelDecline;
  final VoidCallback? onConfirmDecline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      emphasis: !declining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ToneBadge(
                label: 'Nominated as ${_positionWords(position)}',
                tone: Tone.act,
                icon: Icons.how_to_reg_outlined,
                dense: true,
              ),
            ],
          ),
          const Gap.sm(),
          _ThesisTitle(thesisId: thesisId),
          const Gap.md(),
          if (declining) ...[
            FormRow(
              label: 'Reason for declining',
              hint: 'The group and the Research Coordinator will see this.',
              child: TextField(
                key: const Key('declineReason'),
                controller: reason,
                maxLines: 3,
                minLines: 2,
                autofocus: true,
              ),
            ),
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              children: [
                FilledButton(
                  key: const Key('confirmDecline'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tone.returned.color(context),
                  ),
                  onPressed: busy ? null : onConfirmDecline,
                  child: const Text('Confirm decline'),
                ),
                TextButton(
                  onPressed: busy ? null : onCancelDecline,
                  child: const Text('Keep the request'),
                ),
              ],
            ),
          ] else
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: Key('accept-$thesisId'),
                  onPressed: busy ? null : onAccept,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Accept'),
                ),
                OutlinedButton(
                  key: Key('decline-$thesisId'),
                  onPressed: busy ? null : onStartDecline,
                  child: const Text('Decline'),
                ),
                if (busy)
                  Text('Recording your answer…', style: text.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

class _ThesisTitle extends ConsumerWidget {
  const _ThesisTitle({required this.thesisId});

  final String thesisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesis = ref.watch(thesisRepositoryProvider).watchThesis(thesisId);
    return StreamBuilder(
      stream: thesis,
      builder: (context, snap) => Text(
        snap.data?.workingTitle ?? '…',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}
