import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/thesis_queue.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Every thesis at title defence, with a way into each one — for the Dean,
/// who records the decision, and the Coordinator, who sits ex officio.
///
/// Queries `theses` by status directly, which the rules permit to both.
class DefenceQueue extends ConsumerWidget {
  const DefenceQueue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defencesAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.titlePendingDefence));

    if (defencesAsync.valueOrNull?.isEmpty ?? false) {
      return const EmptyState(
        key: Key('noDefences'),
        icon: Icons.forum_outlined,
        title: 'No defences waiting',
        message: 'A thesis appears here once its group has submitted their '
            'candidate titles.',
      );
    }

    return ThesisQueue(
      theses: defencesAsync,
      waitingSince: (t) => t.titlesSubmittedAt,
      errorMessage: 'Could not load the title defences.',
      emptyTitle: 'No defences waiting',
      emptyMessage: '',
      rowAction: (context, t) => FilledButton.tonal(
        key: Key('goToDefence-${t.id}'),
        onPressed: () => context.push('/defence/${t.id}'),
        child: const Text('Open defence'),
      ),
    );
  }
}
