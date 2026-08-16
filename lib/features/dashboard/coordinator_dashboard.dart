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
      onDestinationSelected: _noop,
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
          ],
        ),
      ),
    );
  }
}

void _noop(int _) {}
