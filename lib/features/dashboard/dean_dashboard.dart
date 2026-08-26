import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/features/dashboard/approvals_screen.dart';
import 'package:ethesishub/features/dashboard/dean_overview.dart';
import 'package:ethesishub/features/dashboard/readiness_screen.dart';
import 'package:ethesishub/features/dashboard/title_defences_screen.dart';
import 'package:ethesishub/features/defence/defences_screen.dart';

class DeanDashboard extends ConsumerStatefulWidget {
  const DeanDashboard({super.key});

  @override
  ConsumerState<DeanDashboard> createState() => _DeanDashboardState();
}

class _DeanDashboardState extends ConsumerState<DeanDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('deanDashboard'),
      title: 'eThesisHub',
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      // Overview is prepended ahead of everything else, which shifts every
      // other destination's index by one: Approvals(1), Titles(2),
      // Defences(3), Readiness(4). The body switch below is recomputed
      // against these positions rather than merely offset from the old
      // ones.
      // Three sections that were stacked on one scrolling page, each now
      // its own destination. They answer different questions on different
      // days -- who needs a decision, who is defending, who is ready to be
      // scheduled -- and stacking them made the newest the least visible.
      destinations: const [
        NavDestination(label: 'Overview', icon: Icons.dashboard_outlined),
        NavDestination(label: 'Approvals', icon: Icons.gavel_outlined),
        // Two different jobs, so two destinations. Approving a candidate
        // title set is not attending a scheduled defence, and stacking
        // them put an empty title queue above the rooms that had content.
        NavDestination(label: 'Titles', icon: Icons.forum_outlined),
        NavDestination(label: 'Defences', icon: Icons.event_note_outlined),
        NavDestination(label: 'Readiness', icon: Icons.checklist_outlined),
      ],
      actions: const [SignOutButton()],
      body: switch (_selectedIndex) {
        1 => const ApprovalsScreen(),
        2 => const TitleDefencesScreen(),
        3 => const DefencesScreen(),
        4 => const ReadinessScreen(),
        _ => const DeanOverview(),
      },
    );
  }
}
