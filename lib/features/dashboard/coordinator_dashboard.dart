import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/features/dashboard/coordinator_overview.dart';
import 'package:ethesishub/features/dashboard/readiness_screen.dart';
import 'package:ethesishub/features/dashboard/recommendations_screen.dart';
import 'package:ethesishub/features/dashboard/title_defences_screen.dart';
import 'package:ethesishub/features/defence/defences_screen.dart';

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
        1 => const RecommendationsScreen(),
        2 => const TitleDefencesScreen(),
        3 => const DefencesScreen(),
        4 => const ReadinessScreen(),
        _ => const CoordinatorOverview(),
      },
    );
  }
}
