import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
/// Nothing routes to this screen yet — see Task 15. It needs two links: one
/// from a coordinator's landing area to
/// `ReviewQueueScreen(queue: ThesisStatus.nominationPendingCoordinator,
/// isDean: false)`, and one from the dean's to
/// `ReviewQueueScreen(queue: ThesisStatus.nominationPendingDean,
/// isDean: true)`.
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

  // Created once, not fresh on every build. A `StreamBuilder` recreated each
  // build (as `_act`'s own `setState` calls trigger) tears down and
  // resubscribes its stream every time — `fake_cloud_firestore`'s query
  // listener never delivered a first event to the resubscribed stream in
  // that churn, which hung `recommend`'s own internal `watchThesis(...)
  // .first` read forever (same doc, listener churn mid-flight). Caching the
  // stream keeps one stable subscription for the widget's lifetime.
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDean
            ? 'Nomination approvals'
            : 'Nomination recommendations'),
      ),
      body: StreamBuilder(
        stream: _queueStream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final theses = snap.data!;
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
              if (theses.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text('Nothing waiting.', key: Key('empty')),
                  ),
                )
              else
                for (final t in theses)
                  Card(
                    child: ListTile(
                      title: Text(t.workingTitle),
                      subtitle: Text(
                          '${t.program} · ${t.semester} · ${t.academicYear}'),
                      trailing: FilledButton(
                        key: Key('act-${t.id}'),
                        onPressed: (uid == null || _busy.contains(t.id))
                            ? null
                            : () => _act(uid, t.id),
                        child: Text(label),
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
