import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/thesis_queue.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// The Title defence stage of the Defences page (spec 2026-09-25 §6.2).
///
/// Everyone but a student gets the title defences they can open, each with
/// a way in. A student gets where their own titles stand, never the room:
/// the remarks are not theirs to watch while the panel deliberates.
class TitleDefenceStage extends ConsumerWidget {
  const TitleDefenceStage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    if (!me.hasValue) {
      return me.hasError
          ? ErrorState(error: me.error, message: 'Could not load your account.')
          : const LoadingState(label: 'Loading title defences…');
    }
    final role = me.value?.role;
    if (role == UserRole.student) return const _StudentTitleCard();

    return ThesisQueue(
      theses: ref.watch(myTitleDefencesProvider),
      waitingSince: (t) => t.titlesSubmittedAt,
      errorMessage: 'Could not load the title defences.',
      emptyTitle: 'No title defences',
      emptyMessage: role == UserRole.faculty
          ? 'None of your theses are at title defence right now.'
          : 'A thesis appears here once its group has submitted their '
                'candidate titles.',
      rowAction: (context, t) => FilledButton.tonal(
        key: Key('goToDefence-${t.id}'),
        onPressed: () => context.push('/defence/${t.id}'),
        child: const Text('Open title defence'),
      ),
    );
  }
}

class _StudentTitleCard extends ConsumerWidget {
  const _StudentTitleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(myThesisProvider)
        .when(
          loading: () => const LoadingState(label: 'Loading your thesis…'),
          error: (e, _) =>
              ErrorState(error: e, message: 'Could not load your thesis.'),
          data: (thesis) {
            if (thesis == null) {
              return const EmptyState(
                icon: Icons.groups_outlined,
                title: 'No thesis yet',
                message:
                    'Your title defence appears here once your group '
                    'has a thesis.',
              );
            }
            return Panel(
              key: const Key('studentTitleCard'),
              title: 'Title defence',
              icon: Icons.forum_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _message(thesis),
                  if (thesis.status == ThesisStatus.titleRejected) ...[
                    const Gap.md(),
                    FilledButton.tonal(
                      key: const Key('resubmitTitles'),
                      onPressed: () =>
                          context.push('/thesis/titles?id=${thesis.id}'),
                      child: const Text('Submit new titles'),
                    ),
                  ],
                ],
              ),
            );
          },
        );
  }

  Widget _message(Thesis thesis) => switch (thesis.status) {
    ThesisStatus.titlePendingDefence => const Text(
      'Your candidate titles are with the panel.',
      key: Key('studentTitleMessage'),
    ),
    ThesisStatus.titleRejected => const Text(
      'The panel returned your titles. Submit a new set.',
      key: Key('studentTitleMessage'),
    ),
    ThesisStatus.titleApproved ||
    ThesisStatus.archived => _ApprovedTitle(thesis: thesis),
    _ => const Text(
      'Your group has not submitted candidate titles yet.',
      key: Key('studentTitleMessage'),
    ),
  };
}

/// "Title approved: <the approved candidate>", or a plain sentence while the
/// candidate is still loading or cannot be read.
class _ApprovedTitle extends ConsumerWidget {
  const _ApprovedTitle({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvedId = thesis.approvedTitleId;
    final candidates = ref
        .watch(candidateTitlesProvider(thesis.id))
        .valueOrNull;
    String? text;
    for (final c in candidates ?? const []) {
      if (c.id == approvedId) text = c.titleText;
    }
    return Text(
      text == null ? 'Your title has been approved.' : 'Title approved: $text',
      key: const Key('studentTitleMessage'),
    );
  }
}
