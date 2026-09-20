import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The review queue for the Research Coordinator and the Dean. One screen
/// serves both roles, distinguished entirely by the two constructor
/// parameters: `queue` selects which `ThesisStatus` this instance lists
/// (`nominationPendingCoordinator` or `nominationPendingDean`), and `isDean`
/// selects which `ThesisRepository` method the act button calls
/// (`recommend` vs `approve`).
///
/// Role separation is not re-checked here — it is enforced by
/// `firestore.rules` (`isCoordinator()`/`isDean()` gate both the `list` on
/// theses and the `update` transitions themselves), which is the only real
/// authorization boundary. This screen's own scoping (each instance only
/// ever queries and only ever calls the one method matching its `queue`/
/// `isDean` pair) means an ordinary faculty member or student who somehow
/// reached this screen still cannot act: `thesisRepositoryProvider.approve`/
/// `.recommend` write through to Firestore, which rejects them server-side
/// regardless of what the client attempted.
///
/// `recommend`/`approve` throw `StateError` when the thesis has already left
/// the stage this screen acts on by the time the write lands (e.g. two
/// coordinators both have the queue open; one recommends, and the other's
/// stale list still shows the thesis until its stream catches up). That is
/// surfaced as a plain human message here, not a raw error, and busy state
/// is cleared on every path so the button is left tappable again afterward
/// — matching `nomination_inbox_screen.dart`'s handling of the same class of
/// race for `respondToNomination`.
///
/// Both roles reach this screen at `/review`, which the router resolves to
/// the matching pair: a coordinator gets
/// `queue: ThesisStatus.nominationPendingCoordinator, isDean: false`, the
/// dean gets `queue: ThesisStatus.nominationPendingDean, isDean: true`.
class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({
    super.key,
    required this.queue,
    required this.isDean,
  });

  final ThesisStatus queue;
  final bool isDean;

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  String? _error;
  final Set<String> _busy = {};

  // Created once, in a field, rather than fresh in `build`. This is the
  // standard `StreamBuilder` discipline and it is required on its own terms
  // here: `_act` calls `setState` (busy state, error text) on every tap, and a
  // stream constructed inside `build` would be a NEW object each time, so
  // `StreamBuilder` would cancel its subscription and resubscribe on every
  // rebuild. Against real Firestore each resubscribe is a fresh listen —
  // billed reads, a dropped snapshot cache, and a visible flash back through
  // `!snap.hasData` to the spinner mid-interaction. One subscription for the
  // widget's lifetime is simply correct, independent of any test setup.
  late final Stream<List<Thesis>> _queueStream =
      ref.read(thesisRepositoryProvider).watchByStatus(widget.queue);

  Future<void> _act(String uid, String thesisId) async {
    if (_busy.contains(thesisId)) return; // guards against a double tap

    setState(() {
      _busy.add(thesisId);
      _error = null;
    });

    try {
      final repo = ref.read(thesisRepositoryProvider);
      if (widget.isDean) {
        await repo.approve(thesisId: thesisId, deanUid: uid);
        // Audit failures must never break the approval they record.
        try {
          await ref.read(auditServiceProvider).log(
                actorUid: uid,
                action: 'nomination.approved',
                targetType: 'thesis',
                targetId: thesisId,
                metadata: {'queue': widget.queue.value},
              );
        } catch (_) {}
      } else {
        await repo.recommend(thesisId: thesisId, coordinatorUid: uid);
      }
      if (mounted) setState(() => _error = null);
    } on StateError catch (_) {
      // Reachable in normal use, not just theoretically: another
      // coordinator/dean acted on this thesis first, and this queue's
      // stream simply hasn't caught up yet.
      if (mounted) {
        setState(() => _error =
            'This thesis has already moved on — someone else acted on it '
            'first.');
      }
    } on FirebaseException catch (_) {
      // Checked before the catch-all: FirebaseAuthException is itself a
      // subtype of FirebaseException, so a specific-to-general catch order
      // matters here even though this call never touches auth.
      if (mounted) setState(() => _error = 'Could not record the decision.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record the decision.');
    } finally {
      if (mounted) setState(() => _busy.remove(thesisId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read lazily inside the tap handler — reading it for the
    // first time inside _act can see a stale null before the auth stream's
    // first event has landed.
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final label = widget.isDean ? 'Approve' : 'Recommend';

    // No Scaffold and no AppBar: the app shell owns both. The bar's title
    // still differs by role — see `shellTitleFor`, which asks the same
    // question ('/review' for a dean approves, for a coordinator
    // recommends) one level up.
    return KeyedSubtree(
      key: const Key('reviewQueueScreen'),
      child: StreamBuilder(
        stream: _queueStream,
        builder: (context, snap) {
          final theses = snap.data;
          return PageShell(
            maxWidth: AppTokens.measureWide,
            kicker: widget.isDean ? 'Office of the Dean' : 'Research office',
            title: widget.isDean
                ? 'Approve nominations'
                : 'Recommend nominations',
            subtitle: widget.isDean
                ? 'The Coordinator has recommended each of these. Check the '
                    'roster, then approve to issue Form 1.'
                : 'Every nominee below has accepted. Check the roster, then '
                    'recommend each to the Dean.',
            children: [
              if (_error != null) ...[
                ErrorState(key: const Key('error'), message: _error!),
                const Gap.md(),
              ],
              if (snap.hasError)
                ErrorState(
                    error: snap.error,
                    message: 'Could not load this queue.')
              else if (theses == null)
                const LoadingState(label: 'Loading the queue…')
              else if (theses.isEmpty)
                const EmptyState(
                  key: Key('empty'),
                  icon: Icons.task_alt_rounded,
                  title: 'Nothing waiting',
                  message: 'Every nomination in this queue has been decided.',
                )
              else
                for (final t in theses) ...[
                  _DecisionCard(
                    thesis: t,
                    actionKey: Key('act-${t.id}'),
                    label: label,
                    busy: _busy.contains(t.id),
                    onAct: uid == null ? null : () => _act(uid, t.id),
                  ),
                  const Gap.md(),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// One nomination under review: the group, and the roster being signed
/// off, beside the decision button.
class _DecisionCard extends ConsumerStatefulWidget {
  const _DecisionCard({
    required this.thesis,
    required this.actionKey,
    required this.label,
    required this.busy,
    required this.onAct,
  });

  final Thesis thesis;
  final Key actionKey;
  final String label;
  final bool busy;
  final VoidCallback? onAct;

  @override
  ConsumerState<_DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends ConsumerState<_DecisionCard> {
  // One subscription for the card's lifetime (see the queue stream note).
  late final Stream<List<Nomination>> _nominations = ref
      .read(thesisRepositoryProvider)
      .watchNominations(widget.thesis.id);

  static String _position(NominationPosition p) => switch (p) {
        NominationPosition.adviser => 'Adviser',
        NominationPosition.panelist => 'Panel member',
        NominationPosition.coordinator => 'Research Coordinator',
        NominationPosition.dean => 'Dean',
      };

  @override
  Widget build(BuildContext context) {
    final t = widget.thesis;
    final text = Theme.of(context).textTheme;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(t.status, dense: true),
        const Gap.sm(),
        Text(t.workingTitle, style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          [t.program, t.semester, t.academicYear]
              .where((x) => x.isNotEmpty)
              .join(', '),
          style: text.bodySmall,
        ),
        if (t.memberNames.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Members: ${t.memberNames.join(', ')}', style: text.bodySmall),
        ],
        const Gap.md(),
        FilledButton.icon(
          key: widget.actionKey,
          onPressed: widget.busy ? null : widget.onAct,
          icon: widget.busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined, size: 18),
          label: Text(widget.label),
        ),
      ],
    );

    final roster = StreamBuilder<List<Nomination>>(
      stream: _nominations,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorState(
              error: snap.error, message: 'Could not load the roster.');
        }
        final list = snap.data;
        if (list == null) return const LoadingState();
        final sorted = [...list]
          ..sort((a, b) => a.position.index.compareTo(b.position.index));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Roster', style: text.labelMedium),
            for (final n in sorted)
              PersonLine(
                name: n.nomineeName,
                role: n.exOfficio
                    ? '${_position(n.position)}, ex officio'
                    : _position(n.position),
                trailing: switch (n.conformeStatus) {
                  ConformeStatus.accepted => const ToneBadge(
                      label: 'Accepted', tone: Tone.endorsed, dense: true),
                  ConformeStatus.declined => const ToneBadge(
                      label: 'Declined', tone: Tone.returned, dense: true),
                  ConformeStatus.pending => const ToneBadge(
                      label: 'Pending', tone: Tone.awaiting, dense: true),
                  ConformeStatus.exOfficio => const ToneBadge(
                      label: 'Ex officio', tone: Tone.neutral, dense: true),
                },
              ),
          ],
        );
      },
    );

    return Panel(
      emphasis: true,
      child: SplitColumns(
        stackBelow: 720,
        primaryFlex: 5,
        secondaryFlex: 4,
        primary: [identity],
        secondary: [roster],
      ),
    );
  }
}
