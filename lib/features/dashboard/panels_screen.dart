import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// The panelist mode's own destination on the faculty dashboard: theses
/// whose candidate titles are ready for you to review as a panel member.
class PanelsScreen extends ConsumerWidget {
  const PanelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myThesisIdsAsync = ref.watch(myThesisIdsProvider);

    return PageShell(
      key: const Key('panelsScreen'),
      title: 'My panels',
      subtitle: 'Theses whose candidate titles are ready for you to review '
          'as a panel member.',
      children: [
        myThesisIdsAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(
            error: e,
            message: 'Could not load your panels.',
          ),
          data: (thesisIds) => _DefencesList(thesisIds: thesisIds),
        ),
      ],
    );
  }
}

/// Resolves each thesis id the signed-in faculty member holds a position on
/// and lists the ones currently at [ThesisStatus.titlePendingDefence].
///
/// A separate widget because it watches one [thesisByIdProvider] per id --
/// a dynamic number of family instances that the parent's single build
/// cannot loop over with `ref.watch` outside of a build method of its own.
class _DefencesList extends ConsumerWidget {
  const _DefencesList({required this.thesisIds});

  final List<String> thesisIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (thesisIds.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No defences yet',
        message: 'When you are nominated on a thesis whose candidate titles '
            'reach the panel, it appears here.',
      );
    }

    final rows = <Widget>[];
    for (final id in thesisIds) {
      final thesis = ref.watch(thesisByIdProvider(id)).valueOrNull;
      if (thesis == null || thesis.status != ThesisStatus.titlePendingDefence) {
        continue;
      }
      rows.add(
        Card(
          child: ListTile(
            title: Text(thesis.workingTitle),
            subtitle: const Text(
                'Candidate titles are ready for the panel to review.'),
            trailing: FilledButton(
              key: Key('goToDefence-$id'),
              onPressed: () => context.push('/defence/$id'),
              child: const Text('Open'),
            ),
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No defences waiting',
        message: 'None of your theses are currently at title defence.',
      );
    }

    return Column(children: rows);
  }
}
