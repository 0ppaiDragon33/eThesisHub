import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';

class DeanDashboard extends ConsumerWidget {
  const DeanDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: const [
        NavDestination(label: 'Overview', icon: Icons.dashboard),
        NavDestination(label: 'Approvals', icon: Icons.approval),
      ],
      actions: const [SignOutButton()],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('College Overview'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('goToReview'),
              onPressed: () => context.go('/review'),
              child: const Text('Nomination approvals'),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop(int _) {}
