import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/defence_queue.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class DeanDashboard extends ConsumerWidget {
  const DeanDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('deanDashboard'),
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      // Only approvals resolve today; 'Overview' was a label for the screen
      // you are already on, and defences and reports belong to unbuilt
      // modules.
      destinations: const [],
      actions: const [SignOutButton()],
      body: PageShell(
        title: 'Nomination approvals',
        subtitle: 'Theses the Coordinator has recommended, waiting on you.',
        children: [
          queueAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(
              error: e,
              message: 'Could not load the approval queue.',
            ),
            data: (theses) {
              if (theses.isEmpty) {
                return const EmptyState(
                  icon: Icons.task_alt,
                  title: 'Nothing waiting',
                  message: 'Nominations appear here once the College '
                      'Research Coordinator has recommended them.',
                );
              }
              return Column(
                children: [
                  for (final t in theses)
                    ListTile(
                      title: Text(t.workingTitle),
                      subtitle: Text('${t.program} · ${t.college}'),
                      trailing: StatusChip(t.status, dense: true),
                    ),
                ],
              );
            },
          ),
          const Gap.lg(),
          FilledButton(
            key: const Key('goToReview'),
            onPressed: () => context.go('/review'),
            child: const Text('Open approval queue'),
          ),
          const Gap.lg(),
          // The title defence was reachable only from the faculty
          // dashboard, which the router forbids this role — so the one
          // actor who records the decision could not open the screen.
          // Placed below the nomination actions rather than above them,
          // so the queue this dashboard was built around keeps the top
          // of the page.
          Text('Title defences',
              style: Theme.of(context).textTheme.titleMedium),
          const Gap.sm(),
          Text(
            'Groups presenting their candidate titles. You are the only person who can approve one or reject the set.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap.sm(),
          const DefenceQueue(),
          const Gap.lg(),
          // Which theses have become ready for a pre-oral or final defence,
          // derived from their chapters rather than a stored flag -- see
          // the comment on readinessOf. Placed below the title-defence
          // queue this dashboard already had, for the same reason: it is
          // the newer section.
          Text('Defence readiness',
              style: Theme.of(context).textTheme.titleMedium),
          const Gap.sm(),
          Text(
            'Theses whose chapters have cleared the gate for a pre-oral or '
            'final defence.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap.sm(),
          const DefenceReadinessList(),
        ],
      ),
    );
  }
}
