import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';

class FacultyDashboard extends ConsumerWidget {
  const FacultyDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Groups', icon: Icons.groups),
        NavDestination(label: 'Defenses', icon: Icons.event),
      ],
      body: Center(child: Text('My Advisees')),
    );
  }
}

void _noop(int _) {}
