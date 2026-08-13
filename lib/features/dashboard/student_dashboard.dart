import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';

class StudentDashboard extends ConsumerWidget {
  const StudentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Thesis', icon: Icons.description),
        NavDestination(label: 'Archive', icon: Icons.library_books),
      ],
      actions: [SignOutButton()],
      body: Center(child: Text('My Thesis')),
    );
  }
}

void _noop(int _) {}
