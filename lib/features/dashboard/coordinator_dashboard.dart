import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/coordinator_overview.dart';
import 'package:ethesishub/features/dashboard/defence_queue.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
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

    // Overview is prepended ahead of everything else, which shifts every
    // other destination's index by one: Recommendations(1), Titles(2),
    // Defences(3), Readiness(4), Faculty(5). Hoisted into a local so both
    // this widget and `onDestinationSelected` below read the same list --
    // two copies of this list previously drifted (see that callback's own
    // comment), and cannot again if there is only one.
    final destinations = const [
      NavDestination(label: 'Overview', icon: Icons.dashboard_outlined),
      NavDestination(
          label: 'Recommendations', icon: Icons.fact_check_outlined),
      // Two different jobs, so two destinations. Approving a candidate
      // title set is not attending a scheduled defence, and stacking
      // them put an empty title queue above the rooms that had content.
      NavDestination(label: 'Titles', icon: Icons.forum_outlined),
      NavDestination(label: 'Defences', icon: Icons.event_note_outlined),
      NavDestination(label: 'Readiness', icon: Icons.checklist_outlined),
      NavDestination(label: 'Faculty', icon: Icons.badge_outlined),
    ];

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('coordinatorDashboard'),
      title: 'eThesisHub',
      selectedIndex: _selectedIndex,
      // Driven off the label rather than an index literal. Prepending
      // Overview shifted Faculty from index 4 to index 5, and the previous
      // `if (i == 4)` would have silently sent the Readiness tap to
      // /invites instead -- no error, just the wrong screen. Reading the
      // label off the same `destinations` list the widget itself renders
      // means a future insertion cannot break this again.
      onDestinationSelected: (i) {
        if (destinations[i].label == 'Faculty') {
          context.go('/invites');
          return;
        }
        setState(() => _selectedIndex = i);
      },
      destinations: destinations,
      actions: const [SignOutButton()],
      body: switch (_selectedIndex) {
        1 => PageShell(
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
        2 => const PageShell(
            title: 'Title defences',
            subtitle: 'Groups presenting their candidate titles.',
            children: [DefenceQueue()],
          ),
        3 => const PageShell(
            title: 'Scheduled defences',
            subtitle: 'Pre-oral and final defences, and the rooms they run '
                'in.',
            children: [DefencesList()],
          ),
        4 => const PageShell(
            title: 'Defence readiness',
            subtitle: 'Theses whose chapters have cleared the gate for a '
                'pre-oral or final defence.',
            children: [DefenceReadinessList()],
          ),
        _ => const CoordinatorOverview(),
      },
    );
  }
}
