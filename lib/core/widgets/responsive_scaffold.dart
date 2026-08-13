import 'package:flutter/material.dart';

class NavDestination {
  const NavDestination({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Bottom navigation on narrow screens, navigation rail on wide ones.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.actions,
  });

  static const double railBreakpoint = 900;

  final String title;
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= railBreakpoint;

        return Scaffold(
          appBar: AppBar(title: Text(title), actions: actions),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        label: d.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
