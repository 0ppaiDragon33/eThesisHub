import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
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

    final confirmed = await confirmAction(
      context,
      title: 'Reopen this thesis for re-nomination?',
      message: 'It goes back to the group as a draft. Nominees who already '
          'accepted keep their seat; the group replaces whoever declined.',
      confirmLabel: 'Reopen',
      confirmKey: Key('confirmReopen-$thesisId'),
    );
    if (!confirmed || !mounted) return;

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
    const title = 'Stalled nominations';
    const subtitle = 'A nominee declined on each of these, so the thesis '
        'cannot advance. Reopening returns it to draft so the group can '
        'nominate again.';

    return KeyedSubtree(
      key: const Key('stalledThesesScreen'),
      child: PageShell(
        kicker: 'Research office',
        title: title,
        subtitle: subtitle,
        children: [
          if (_error != null) ...[
            ErrorState(key: const Key('error'), message: _error!),
            const Gap.md(),
          ],
          stalled.when(
            loading: () => const LoadingState(
              key: Key('stalledLoading'),
              label: 'Checking nominations…',
            ),
            // Distinct from "nothing is stuck".
            error: (e, _) => ErrorState(
              key: const Key('stalledError'),
              error: e,
              message: 'Could not load stalled theses.',
            ),
            data: (theses) => theses.isEmpty
                ? const EmptyState(
                    key: Key('empty'),
                    icon: Icons.done_all_rounded,
                    title: 'Nothing is stuck',
                    message: 'Every nomination in progress is still waiting '
                        'on answers, not blocked by a decline.',
                  )
                : Panel(
                    flush: true,
                    child: Column(
                      children: [
                        for (final t in theses)
                          RecordRow(
                            leading: Icon(Icons.report_outlined,
                                color: Tone.returned.color(context)),
                            title: t.workingTitle,
                            subtitle: [t.program, t.academicYear]
                                .where((x) => x.isNotEmpty)
                                .join(', '),
                            trailing: FilledButton(
                              key: Key('reopen-${t.id}'),
                              onPressed: (uid == null || _busy.contains(t.id))
                                  ? null
                                  : () => _reopen(uid, t.id),
                              child: const Text('Reopen'),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
