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
import 'package:ethesishub/providers/thesis_providers.dart';

class CoordinatorDashboard extends ConsumerWidget {
  const CoordinatorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator));

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('coordinatorDashboard'),
      title: 'eThesisHub',
      selectedIndex: 0,
      // The coordinator is the one role with two real places to be, so this
      // is the only dashboard whose navigation shows. 'Defenses' and
      // 'Reports' arrive with their modules.
      onDestinationSelected: (i) {
        if (i == 1) context.go('/invites');
      },
      destinations: const [
        NavDestination(label: 'Theses', icon: Icons.folder_outlined),
        NavDestination(label: 'Faculty', icon: Icons.badge_outlined),
      ],
      actions: const [SignOutButton()],
      body: PageShell(
        title: 'Nomination recommendations',
        subtitle: 'Theses whose nominees have all accepted, waiting on you.',
        children: [
          queueAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(
              error: e,
              message: 'Could not load the review queue.',
            ),
            data: (theses) {
              if (theses.isEmpty) {
                return const EmptyState(
                  icon: Icons.task_alt,
                  title: 'Nothing waiting',
                  message: 'A thesis appears here once every nominee has '
                      'accepted their Conforme.',
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
            child: const Text('Open review queue'),
          ),
          const Gap.sm(),
          OutlinedButton(
            key: const Key('goToFaculty'),
            onPressed: () => context.go('/invites'),
            child: const Text('Invite faculty'),
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
            'Groups presenting their candidate titles. You sit on every panel ex officio and may comment on any candidate.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap.sm(),
          const DefenceQueue(),
        ],
      ),
    );
  }
}
