import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The adviser mode's own destination on the faculty dashboard: the theses
/// you advise, with a count of chapters awaiting your review.
class AdviseesScreen extends ConsumerWidget {
  const AdviseesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adviseesAsync = ref.watch(myAdviseesProvider);

    return PageShell(
      key: const Key('adviseesScreen'),
      title: 'My advisees',
      subtitle: 'Chapters I–V for each thesis you advise.',
      children: [
        // Its own loading and error handling. Collapsing this into
        // `data(const [])` while the query is in flight renders an empty
        // state indistinguishable from "no advisees" — a bug this project
        // has shipped four times.
        adviseesAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(
            error: e,
            message: 'Could not load your advisees.',
          ),
          data: (advisees) => advisees.isEmpty
              ? const EmptyState(
                  icon: Icons.school_outlined,
                  title: 'No advisees yet',
                  message: 'Once a group nominates you as adviser and the '
                      'Dean approves, their thesis appears here.',
                )
              : Column(
                  children: [
                    for (final thesis in advisees)
                      _AdviseeCard(thesis: thesis),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One advisee's row, with a count of chapters `submitted` -- uploaded by
/// the student, not yet responded to by the adviser.
///
/// Spec §7 requires this count ("advised theses with a count of chapters
/// awaiting review") so an adviser with several advisees can tell which
/// groups have work waiting without opening every one and clicking through
/// every chapter. A separate widget, same shape as `_DefencesList` in
/// `panels_screen.dart`: a dynamic number of `chaptersProvider` family
/// instances cannot be looped over with `ref.watch` inside the parent's
/// single build.
class _AdviseeCard extends ConsumerWidget {
  const _AdviseeCard({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider(thesis.id));

    return Card(
      child: ListTile(
        key: Key('advisee-${thesis.id}'),
        title: Text(thesis.workingTitle),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${thesis.college} • ${thesis.program}'),
            // While the stream is still loading, this must NOT read "0
            // awaiting" -- that is indistinguishable from nothing actually
            // waiting, the single most repeated bug in this codebase (see
            // `_ReadinessRow` in defence_readiness.dart and `_DefencesList`
            // above, which apply the same rule).
            chaptersAsync.when(
              loading: () => const Text('Awaiting review: still loading…'),
              error: (e, _) =>
                  const Text('Could not load this thesis\'s chapters.'),
              data: (chapters) {
                final awaiting = chapters
                    .where((c) => c.status == ChapterStatus.submitted)
                    .length;
                return Text(awaiting == 0
                    ? 'Nothing awaiting review'
                    : awaiting == 1
                        ? '1 chapter awaiting review'
                        : '$awaiting chapters awaiting review');
              },
            ),
          ],
        ),
        trailing: FilledButton(
          key: Key('openChapters-${thesis.id}'),
          onPressed: () => context.go('/thesis/chapters?id=${thesis.id}'),
          child: const Text('Open'),
        ),
      ),
    );
  }
}
