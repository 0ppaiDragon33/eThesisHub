import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';

class CoordinatorDashboard extends ConsumerWidget {
  const CoordinatorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      // 'Faculty' now leads somewhere. 'Defenses' is still inert — that
      // module is not built — and a tab that silently does nothing reads as
      // a broken app rather than an unbuilt one, so it should either lead
      // somewhere or be removed before the defence.
      onDestinationSelected: (i) {
        if (i == 1) context.go('/faculty');
      },
      destinations: const [
        NavDestination(label: 'Theses', icon: Icons.folder),
        NavDestination(label: 'Faculty', icon: Icons.badge),
        NavDestination(label: 'Defenses', icon: Icons.event),
      ],
      actions: const [SignOutButton()],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('All Theses'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('goToReview'),
              onPressed: () => context.go('/review'),
              child: const Text('Nomination recommendations'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const Key('goToFaculty'),
              onPressed: () => context.go('/faculty'),
              child: const Text('Invite faculty'),
            ),
          ],
        ),
      ),
    );
  }
}

