import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Under a Fail verdict with no re-defence yet (spec 2026-09-25 §6.5): the
/// Coordinator's way to schedule it, or, for everyone else, word that it is
/// coming.
///
/// Whether the re-defence exists is read from the reader's own defence
/// list, never by fetching the derived id: the rules deny `get` on a
/// missing defence document.
class RedefenceNotice extends ConsumerWidget {
  const RedefenceNotice({super.key, required this.defence});

  final Defence defence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defence.panelVerdict != PassFail.fail || defence.isRedefence) {
      return const SizedBox.shrink();
    }
    final all = ref.watch(myDefencesProvider).valueOrNull;
    // Until the list arrives, say nothing, rather than offer a re-defence
    // that may already exist.
    if (all == null || hasRedefence(defence, all)) {
      return const SizedBox.shrink();
    }
    final isCoordinator =
        ref.watch(currentUserProvider).valueOrNull?.role ==
        UserRole.coordinator;
    if (isCoordinator) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('scheduleRedefence'),
          onPressed: () =>
              context.push('/defence/schedule?redefenceOf=${defence.id}'),
          icon: const Icon(Icons.replay_outlined, size: 18),
          label: const Text('Schedule re-defence'),
        ),
      );
    }
    return const Text(
      'A re-defence of this stage is to be scheduled.',
      key: Key('redefencePending'),
    );
  }
}
