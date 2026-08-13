import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';

class CoordinatorDashboard extends ConsumerWidget {
  const CoordinatorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Theses', icon: Icons.folder),
        NavDestination(label: 'Faculty', icon: Icons.badge),
        NavDestination(label: 'Defenses', icon: Icons.event),
      ],
      actions: [SignOutButton()],
      body: Center(child: Text('All Theses')),
    );
  }
}

void _noop(int _) {}
