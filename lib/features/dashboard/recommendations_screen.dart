import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/thesis_queue.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Coordinator's Recommendations destination: nominations whose
/// nominees have all accepted, waiting on the Coordinator.
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator));

    void openReview() => context.push('/review');

    return PageShell(
      key: const Key('recommendationsScreen'),
      maxWidth: AppTokens.measureWide,
      kicker: 'Research office',
      title: 'Nomination recommendations',
      subtitle: 'Every nominee on these theses has accepted. Recommend '
          'each one to the Dean, or return it.',
      actions: [
        OutlinedButton.icon(
          key: const Key('goToFaculty'),
          onPressed: () => context.go('/invites'),
          icon: const Icon(Icons.person_add_alt_outlined, size: 18),
          label: const Text('Invite faculty'),
        ),
        FilledButton(
          key: const Key('goToReview'),
          onPressed: openReview,
          child: const Text('Open review queue'),
        ),
      ],
      children: [
        ThesisQueue(
          theses: queueAsync,
          waitingSince: (t) => t.nominationsSubmittedAt,
          errorMessage: 'Could not load the review queue.',
          emptyTitle: 'Nothing waiting',
          emptyMessage: 'A thesis appears here once every nominee has '
              'accepted their Conforme.',
          rowAction: (context, t) => FilledButton.tonal(
            onPressed: openReview,
            child: const Text('Review'),
          ),
        ),
      ],
    );
  }
}
