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
    this.suppressBackControl = false,
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

  /// True on the app's one designated dead end (`/no-profile`): no
  /// destination owns it, so ownership alone would always draw a back
  /// control there, but tapping it can only fall through to '/overview',
  /// which the redirect immediately bounces straight back. A control that
  /// does nothing is worse than none, so the caller that knows this route
  /// is the dead end suppresses it explicitly rather than `AppShell`
  /// guessing from the location string -- this widget otherwise knows
  /// nothing about any specific route (see the class doc above).
  final bool suppressBackControl;

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
      // `maybePop`, not `pop`: a deep screen reached directly by URL has
      // nothing beneath it in the Navigator stack, and `pop` would throw
      // where `maybePop` simply does nothing.
      Navigator.maybePop(context);
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
    final deep = !loading &&
        !shell.suppressBackControl &&
        isDeeperThanDestination(list, shell.location);
    final owner = loading ? null : destinationForLocation(list, shell.location);
    final selectedIndex = owner == null ? null : list.indexOf(owner);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppShell.railBreakpoint;

        if (loading) {
          if (wide) {
            return Scaffold(
              appBar: AppBar(title: Text(shell.title)),
              body: Row(
                children: [
                  _Skeleton(rule: _rule(context), ink: _ink(context)),
                  const VerticalDivider(width: 1),
                  Expanded(child: shell.child),
                ],
              ),
            );
          }
          // Narrow while loading: the hamburger is still shown so the
          // reader can see navigation is coming, and the drawer it opens
          // holds the same inert skeleton rather than being empty.
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
            ),
            drawer: Drawer(
              child: SafeArea(
                child: _Skeleton(rule: _rule(context), ink: _ink(context)),
              ),
            ),
            body: shell.child,
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
                // Empty rail background, below/around the destination list,
                // toggles the same as the edge strip -- the rail itself is
                // the control, not a button bolted onto it. A plain
                // ancestor `GestureDetector` (not a `Stack` overlay) on
                // purpose: `NavigationRail` owns a custom, non-standard
                // `RenderBox` that does not tolerate the extra dry-layout
                // pass a `Stack` performs to size a non-positioned child --
                // that combination corrupted its semantics bookkeeping
                // (`!semantics.parentDataDirty`) and, at some widths, fed it
                // an unbounded width, in both cases crashing every route
                // test that renders the shell. A `GestureDetector` wrapping
                // the rail as its parent does not touch layout at all --
                // constraints pass straight through -- so it carries none of
                // that risk. `HitTestBehavior.translucent` plus normal
                // gesture-arena resolution means a tap that lands on a real
                // destination (or on the footer's buttons) is still won by
                // that descendant's own recognizer, since descendants join
                // the arena before their ancestor and are swept first; only
                // a tap that hits no descendant reaches this one.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () =>
                      ref.read(sidebarExpandedProvider.notifier).toggle(),
                  child: NavigationRailTheme(
                      // Brings the rail closer to the drawer's proportions
                      // (spec: "doesn't look like navigation unlike
                      // mobile") -- a narrower extended width, and the same
                      // type scale NavigationDrawer uses (labelLarge)
                      // rather than the rail's own, smaller default
                      // (labelMedium). The selected-item indicator pill
                      // stays: that is part of what makes the drawer read
                      // correctly, and nothing here overrides it.
                      data: NavigationRailThemeData(
                        minWidth: 72,
                        minExtendedWidth: 220,
                        selectedLabelTextStyle: Theme.of(context)
                            .textTheme
                            .labelLarge,
                        unselectedLabelTextStyle: Theme.of(context)
                            .textTheme
                            .labelLarge,
                      ),
                      child: NavigationRail(
                        extended: expanded,
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (i) =>
                            shell._navigate(context, list[i].route),
                        // No leading toggle button. The user's own words:
                        // "remove the button entirely and just click the
                        // navbar itself or the side of it" — collapsing is
                        // reached by tapping empty rail space or the edge
                        // strip beside the rail (below), never a dedicated
                        // control. Safe as a hidden affordance only because
                        // collapse exists solely on wide, mouse-driven
                        // screens; a phone gets a drawer with nothing to
                        // collapse.
                        //
                        // `NavigationRail.trailing` is not bottom-aligned
                        // on its own -- without `trailingAtBottom`, it
                        // renders directly beneath the last destination,
                        // which is not "at the foot of the sidebar" (spec
                        // §5.3) once the rail is taller than its
                        // destination list, which is the common case. An
                        // earlier version pinned it with `Expanded` +
                        // `Align` instead: that claims "whatever height is
                        // left after the destinations", which goes negative
                        // on a short rail (a landscape phone, a squat
                        // browser window) and overflows. `trailingAtBottom`
                        // pins the footer at a fixed height without
                        // claiming the remainder, and `scrollable` lets the
                        // destination list itself yield -- become a
                        // scrollable viewport -- when the two together do
                        // not fit, so the footer degrades to "reachable by
                        // scrolling the destinations above it" rather than
                        // overflowing off the bottom.
                        trailingAtBottom: true,
                        scrollable: true,
                        trailing: shell.accountFooter,
                        destinations: [
                          for (final d in list)
                            NavigationRailDestination(
                              icon: Icon(d.icon),
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              // Always the real label. NavigationRail keeps
                              // it mounted (Visibility.maintain) even when
                              // collapsed specifically so the accessible
                              // name survives — swapping in a SizedBox when
                              // collapsed would delete every destination's
                              // accessible name app-wide.
                              label: Text(d.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                _SidebarEdgeToggle(
                  expanded: expanded,
                  ruleColor: _rule(context),
                  onToggle: () =>
                      ref.read(sidebarExpandedProvider.notifier).toggle(),
                ),
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

/// The clickable strip between the rail and the content, on wide screens.
///
/// Replaces both the old `VerticalDivider` and the old `Key('sidebarToggle')`
/// button: the boundary between rail and content is now the only visible
/// affordance, and it does two jobs at once -- it still reads as a divider
/// when idle, and tapping it toggles [sidebarExpandedProvider]. That is safe
/// as a hidden affordance only because collapse exists solely on wide,
/// mouse-driven screens; a phone gets a drawer and a hamburger and has
/// nothing to collapse, so no equivalent exists there.
class _SidebarEdgeToggle extends StatelessWidget {
  const _SidebarEdgeToggle({
    required this.expanded,
    required this.ruleColor,
    required this.onToggle,
  });

  final bool expanded;
  final Color ruleColor;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = expanded ? 'Collapse sidebar' : 'Expand sidebar';

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('sidebarEdgeToggle'),
                canRequestFocus: true,
                onTap: onToggle,
                child: Center(
                  child: Container(width: 1, color: ruleColor),
                ),
              ),
            ),
          ),
        ),
      ),
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
