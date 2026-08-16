import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';

class StudentDashboard extends ConsumerWidget {
  const StudentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: const [
        NavDestination(label: 'Thesis', icon: Icons.description),
        NavDestination(label: 'Archive', icon: Icons.library_books),
      ],
      actions: const [SignOutButton()],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('My Thesis'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('goToThesis'),
              onPressed: () => context.go('/thesis'),
              child: const Text('My thesis'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('goToCreateThesis'),
              onPressed: () => context.go('/thesis/create'),
              child: const Text('Create group'),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop(int _) {}
