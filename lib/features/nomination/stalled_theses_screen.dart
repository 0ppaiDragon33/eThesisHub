import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The coordinator's recovery screen for theses a decline has wedged.
///
/// A declined Conforme is terminal on its own: the nominee cannot
/// un-decline, `respondToNomination` counts them outstanding forever, and
/// the rules freeze the leader out of their own thesis the moment it leaves
/// `draft` — so the group cannot replace the person who declined either.
/// Returning the thesis to `draft` hands it back to them.
///
/// Only theses that are genuinely stuck appear here (see
/// [stalledThesesProvider]); a thesis merely waiting on answers is not the
/// coordinator's problem and would bury the ones that are.
class StalledThesesScreen extends ConsumerStatefulWidget {
  const StalledThesesScreen({super.key});

  @override
  ConsumerState<StalledThesesScreen> createState() =>
      _StalledThesesScreenState();
}

class _StalledThesesScreenState extends ConsumerState<StalledThesesScreen> {
  String? _error;
  final Set<String> _busy = {};

  Future<void> _reopen(String coordinatorUid, String thesisId) async {
    if (_busy.contains(thesisId)) return; // guards against a double tap

    setState(() {
      _busy.add(thesisId);
      _error = null;
    });

    try {
      await ref.read(thesisRepositoryProvider).reopenForRenomination(
            thesisId: thesisId,
            coordinatorUid: coordinatorUid,
          );
      // An audit failure must never break the recovery it records.
      try {
        await ref.read(auditServiceProvider).log(
              actorUid: coordinatorUid,
              action: 'nomination.reopened',
              targetType: 'thesis',
              targetId: thesisId,
            );
      } catch (_) {}
    } on StateError catch (_) {
      // Reachable in normal use: another coordinator reopened it first, or
      // the last outstanding nominee accepted while this screen was open,
      // and the stream has not caught up.
      if (mounted) {
        setState(() => _error =
            'This thesis has already moved on — someone else acted on it '
            'first.');
      }
    } on FirebaseException catch (_) {
      // Checked before the catch-all: FirebaseAuthException is itself a
      // subtype of FirebaseException, so specific-to-general order matters.
      if (mounted) setState(() => _error = 'Could not reopen this thesis.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reopen this thesis.');
    } finally {
      if (mounted) setState(() => _busy.remove(thesisId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read lazily inside the tap handler — reading it there for
    // the first time can see a stale null before the auth stream's first
    // event has landed.
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final stalled = ref.watch(stalledThesesProvider);

    // No Scaffold and no AppBar: the app shell owns both.
    return KeyedSubtree(
      key: const Key('stalledThesesScreen'),
      child: stalled.when(
        loading: () => const Center(
          key: Key('stalledLoading'),
          child: CircularProgressIndicator(),
        ),
        // Distinct from "nothing is stuck". A coordinator who cannot read
        // this must not be told the queue is clear.
        error: (e, _) => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Could not load stalled theses.',
              key: Key('stalledError'),
            ),
          ),
        ),
        data: (theses) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  key: const Key('error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (theses.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                  child: Text('Nothing is stuck.', key: Key('empty')),
                ),
              )
            else
              for (final t in theses)
                Card(
                  child: ListTile(
                    title: Text(t.workingTitle),
                    subtitle: const Text(
                      'A nominee declined, so this thesis cannot advance. '
                      'Reopening returns it to draft for the group to '
                      're-nominate.',
                    ),
                    trailing: FilledButton(
                      key: Key('reopen-${t.id}'),
                      onPressed: (uid == null || _busy.contains(t.id))
                          ? null
                          : () => _reopen(uid, t.id),
                      child: const Text('Reopen'),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
