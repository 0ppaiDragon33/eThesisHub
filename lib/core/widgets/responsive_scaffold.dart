import 'package:flutter/material.dart';

class NavDestination {
  const NavDestination({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Bottom navigation on narrow screens, navigation rail on wide ones — and
/// no navigation at all until there is somewhere to navigate.
///
/// Each dashboard declares only destinations that actually resolve. Modules
/// that are not built yet contribute nothing, so the bar appears on its own
/// as they land rather than sitting there promising screens that do not
/// exist. A control that does nothing when tapped reads as a broken app, not
/// an unfinished one, and that is a usability score this project cannot
/// afford to give away.
///
/// The threshold is two rather than the conventional three: a role with two
/// real places to be is genuinely navigating, and Material's 3–5 guidance is
/// about not overloading a bar, not a floor below which two destinations
/// become wrong.
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

  /// Below this many destinations, the navigation is hidden entirely.
  static const int minDestinations = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= railBreakpoint;
        final showNav = destinations.length >= minDestinations;

        if (!showNav) {
          return Scaffold(
            appBar: AppBar(title: Text(title), actions: actions),
            body: body,
          );
        }

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
