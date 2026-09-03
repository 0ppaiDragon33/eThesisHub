import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Every thesis currently at title defence, with a way into each one.
///
/// The Dean is the only person who can end a title defence, and the
/// Coordinator sits on every panel ex officio — yet neither dashboard offered
/// a route to `/defence/:thesisId`. Only the faculty dashboard linked it, and
/// the router actively sends a dean away from `/faculty`, so the one actor
/// who records the decision had no path to the screen at all.
///
/// Unlike the faculty dashboard's list, this one queries `theses` by status
/// directly: `firestore.rules` already permits `list` on `theses` for a
/// coordinator or a dean, so no rules change is needed and no nomination
/// collection-group hop is required.
class DefenceQueue extends ConsumerWidget {
  const DefenceQueue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defencesAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.titlePendingDefence));

    return defencesAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        message: 'Could not load the title defences.',
      ),
      data: (theses) {
        if (theses.isEmpty) {
          return const EmptyState(
            key: Key('noDefences'),
            icon: Icons.forum_outlined,
            title: 'No defences waiting',
            message: 'A thesis appears here once its group has submitted '
                'their candidate titles.',
          );
        }
        return Column(
          children: [
            for (final t in theses)
              Card(
                child: ListTile(
                  title: Text(t.workingTitle),
                  subtitle: Text('${t.program} · ${t.college}'),
                  trailing: FilledButton(
                    key: Key('goToDefence-${t.id}'),
                    onPressed: () => context.push('/defence/${t.id}'),
                    child: const Text('Open'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
