import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';

class FacultyDashboard extends ConsumerWidget {
  const FacultyDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(facultyModeProvider);
    final holdsAdviserPositions = ref.watch(adviserPositionCountProvider) > 0;
    final pendingElsewhere = ref.watch(pendingInOtherModeProvider);

    return ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        NavDestination(label: 'Groups', icon: Icons.groups),
        NavDestination(label: 'Defenses', icon: Icons.event),
      ],
      actions: [
        if (holdsAdviserPositions)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              isLabelVisible: pendingElsewhere > 0,
              label: Text('$pendingElsewhere'),
              child: SegmentedButton<FacultyMode>(
                segments: const [
                  ButtonSegment(
                    value: FacultyMode.adviser,
                    label: Text('Adviser'),
                  ),
                  ButtonSegment(
                    value: FacultyMode.panelist,
                    label: Text('Panelist'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => ref
                    .read(facultyModeProvider.notifier)
                    .set(selection.first),
              ),
            ),
          ),
        const SignOutButton(),
      ],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mode == FacultyMode.adviser ? 'My Advisees' : 'My Panels'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('goToInbox'),
              onPressed: () => context.go('/nominations'),
              child: const Text('Nomination inbox'),
            ),
          ],
        ),
      ),
    );
  }
}
