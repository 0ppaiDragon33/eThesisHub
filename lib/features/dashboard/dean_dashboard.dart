import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';

class DeanDashboard extends ConsumerWidget {
  const DeanDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Overview', icon: Icons.dashboard),
        NavDestination(label: 'Approvals', icon: Icons.approval),
      ],
      actions: [SignOutButton()],
      body: Center(child: Text('College Overview')),
    );
  }
}

void _noop(int _) {}
