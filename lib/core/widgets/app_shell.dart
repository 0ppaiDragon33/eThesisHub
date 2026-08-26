import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/providers/sidebar_provider.dart';

/// The one chrome every signed-in route sits inside: a collapsible rail on
/// wide screens, a drawer on narrow ones, an app bar, and a back control
/// for anything a destination does not directly own.
///
/// Takes [destinations] and [location] as parameters rather than reading
/// the router or providers itself — that is what makes every case here
/// testable without building a `GoRouter`, and it is why this widget comes
/// before the routing switchover.
///
/// On narrow screens the hamburger never disappears, even on a deep
/// screen: a back control that replaces it would strand a phone reader on
/// an inner page with no way to reach any other destination — the exact
/// trap this milestone exists to close, one level deeper. So on narrow,
/// `leading` is always the hamburger and the back control (when needed)
/// is the first entry in `actions`. On wide, there is no hamburger at all
/// because the rail is already visible, so `leading` holds the back
/// control when the location is deeper than a destination, and is null
/// otherwise.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.destinations,
    required this.location,
    required this.child,
    required this.title,
    this.onNavigate,
    this.onBack,
    this.trailing,
    this.accountFooter,
  });

  static const double railBreakpoint = 900;
  static const int minDestinations = 2;

  final AsyncValue<List<ShellDestination>> destinations;
  final String location;
  final Widget child;
  final String title;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Widget? accountFooter;

  void _navigate(BuildContext context, String route) {
    if (onNavigate != null) {
      onNavigate!(route);
    } else {
      context.go(route);
    }
  }

  void _back(BuildContext context) {
    if (onBack != null) {
      onBack!();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(sidebarExpandedProvider);

    return destinations.when(
      loading: () => _Chrome(
        shell: this,
        ref: ref,
        expanded: expanded,
        list: const [],
        loading: true,
      ),
      error: (e, st) => _Chrome(
        shell: this,
        ref: ref,
        expanded: expanded,
        list: const [],
        loading: false,
      ),
      data: (list) => _Chrome(
        shell: this,
        ref: ref,
        expanded: expanded,
        list: list,
        loading: false,
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.shell,
    required this.ref,
    required this.expanded,
    required this.list,
    required this.loading,
  });

  final AppShell shell;
  final WidgetRef ref;
  final bool expanded;
  final List<ShellDestination> list;
  final bool loading;

  Color _rule(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? AppTokens.ruleDark : AppTokens.rule;
  }

  Color _ink(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? AppTokens.inkMutedDark : AppTokens.inkMuted;
  }

  @override
  Widget build(BuildContext context) {
    final showNav = !loading && list.length >= AppShell.minDestinations;
    final deep = !loading && isDeeperThanDestination(list, shell.location);
    final owner = loading ? null : destinationForLocation(list, shell.location);
    final selectedIndex = owner == null ? null : list.indexOf(owner);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppShell.railBreakpoint;

        if (loading) {
          return Scaffold(
            appBar: AppBar(title: Text(shell.title)),
            body: wide
                ? Row(
                    children: [
                      _Skeleton(rule: _rule(context), ink: _ink(context)),
                      const VerticalDivider(width: 1),
                      Expanded(child: shell.child),
                    ],
                  )
                : shell.child,
          );
        }

        if (!showNav) {
          return Scaffold(
            appBar: AppBar(
              title: Text(shell.title),
              leading: deep
                  ? IconButton(
                      key: const Key('shellBack'),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => shell._back(context),
                    )
                  : null,
              actions: [
                if (shell.trailing != null) shell.trailing!,
              ],
            ),
            body: shell.child,
          );
        }

        if (wide) {
          return Scaffold(
            appBar: AppBar(
              title: Text(shell.title),
              leading: deep
                  ? IconButton(
                      key: const Key('shellBack'),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => shell._back(context),
                    )
                  : null,
              actions: [
                if (shell.trailing != null) shell.trailing!,
              ],
            ),
            body: Row(
              children: [
                NavigationRail(
                  extended: expanded,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (i) =>
                      shell._navigate(context, list[i].route),
                  leading: IconButton(
                    key: const Key('sidebarToggle'),
                    icon: Icon(expanded ? Icons.chevron_left : Icons.chevron_right),
                    onPressed: () =>
                        ref.read(sidebarExpandedProvider.notifier).toggle(),
                  ),
                  trailing: shell.accountFooter,
                  destinations: [
                    for (final d in list)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        // NavigationRail keeps the label widget mounted
                        // (for semantics) even when collapsed, so an
                        // unconditional Text would still be found by
                        // find.text while hidden. Building it from our
                        // own `expanded` flag rather than the rail's
                        // internal animation keeps a collapsed rail
                        // genuinely free of the label text.
                        label: expanded
                            ? Text(d.label)
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: shell.child),
              ],
            ),
          );
        }

        // Narrow, with navigation: the hamburger always stays in leading;
        // the back control, when needed, is the first action.
        return Scaffold(
          appBar: AppBar(
            title: Text(shell.title),
            leading: Builder(
              builder: (context) => IconButton(
                key: const Key('shellMenu'),
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            actions: [
              if (deep)
                IconButton(
                  key: const Key('shellBack'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => shell._back(context),
                ),
              if (shell.trailing != null) shell.trailing!,
            ],
          ),
          drawer: NavigationDrawer(
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) {
              Navigator.pop(context);
              shell._navigate(context, list[i].route);
            },
            children: [
              for (final d in list)
                NavigationDrawerDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
              if (shell.accountFooter != null) shell.accountFooter!,
            ],
          ),
          body: shell.child,
        );
      },
    );
  }
}

/// Inert placeholder rows shown while [AppShell] does not yet know which
/// destinations this account holds. Nothing here is tappable, and no
/// destination label appears — a skeleton cannot misroute; a guessed role
/// can offer a destination the account does not hold.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.rule, required this.ink});

  final Color rule;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Padding(
        key: const Key('shellSkeleton'),
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
                child: Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: rule,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
