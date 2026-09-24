import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/thesis_queue.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Dean's Approvals destination: nominations the Coordinator has
/// recommended, waiting on the Dean's decision.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));

    // '/review' is below every destination, so it is pushed (D23).
    void openReview() => context.push('/review');

    return PageShell(
      key: const Key('approvalsScreen'),
      maxWidth: AppTokens.measureWide,
      kicker: 'Office of the Dean',
      title: 'Nomination approvals',
      subtitle: 'Nominations the Research Coordinator has recommended. '
          'Approving one issues the group\'s Form 1.',
      actions: [
        FilledButton(
          key: const Key('goToReview'),
          onPressed: openReview,
          child: const Text('Open approval queue'),
        ),
      ],
      children: [
        ThesisQueue(
          theses: queueAsync,
          waitingSince: (t) => t.coordinatorRecommendedAt,
          errorMessage: 'Could not load the approval queue.',
          emptyTitle: 'Nothing waiting',
          emptyMessage: 'Nominations appear here once the College Research '
              'Coordinator has recommended them.',
          rowAction: (context, t) => FilledButton.tonal(
            onPressed: openReview,
            child: const Text('Decide'),
          ),
        ),
      ],
    );
  }
}
