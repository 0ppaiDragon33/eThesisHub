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

class CoordinatorDashboard extends ConsumerStatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  ConsumerState<CoordinatorDashboard> createState() =>
      _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends ConsumerState<CoordinatorDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator));

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('coordinatorDashboard'),
      title: 'eThesisHub',
      selectedIndex: _selectedIndex,
      // Three sections that were stacked on one scrolling page, each now
      // its own destination -- they answer different questions on different
      // days, and stacking them made the newest the least visible. Faculty
      // stays a jump to its own screen rather than a panel here, because
      // invites are a different job from reviewing theses.
      onDestinationSelected: (i) {
        if (i == 3) {
          context.go('/invites');
          return;
        }
        setState(() => _selectedIndex = i);
      },
      destinations: const [
        NavDestination(
            label: 'Recommendations', icon: Icons.fact_check_outlined),
        NavDestination(label: 'Defences', icon: Icons.forum_outlined),
        NavDestination(label: 'Readiness', icon: Icons.checklist_outlined),
        NavDestination(label: 'Faculty', icon: Icons.badge_outlined),
      ],
      actions: const [SignOutButton()],
      body: switch (_selectedIndex) {
        1 => const PageShell(
            title: 'Title defences',
            subtitle: 'Groups presenting their candidate titles to the '
                'panel you sit on ex officio.',
            children: [DefenceQueue()],
          ),
        2 => const PageShell(
            title: 'Defence readiness',
            subtitle: 'Theses whose chapters have cleared the gate for a '
                'pre-oral or final defence.',
            children: [DefenceReadinessList()],
          ),
        _ => PageShell(
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
        ],
          ),
      },
    );
  }
}
