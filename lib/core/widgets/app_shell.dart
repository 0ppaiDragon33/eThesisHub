import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/brand.dart';
import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/providers/sidebar_provider.dart';

/// Tells shell content (the account footer, mainly) where it is drawn, so
/// one widget can serve the dark sidebar, its collapsed form, and the
/// phone's drawer without measuring the screen itself.
class ShellPlacement extends InheritedWidget {
  const ShellPlacement({
    super.key,
    required this.inSidebar,
    required this.collapsed,
    required super.child,
  });

  final bool inSidebar;
  final bool collapsed;

  static ShellPlacement? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellPlacement>();

  @override
  bool updateShouldNotify(ShellPlacement old) =>
      inSidebar != old.inSidebar || collapsed != old.collapsed;
}

/// The chrome every signed-in route sits inside.
///
/// - Wide (≥ [railBreakpoint]): an ink sidebar on the left — full width at
///   ≥ [fullSidebarFrom] unless the reader collapsed it, icons only below
///   that — and a paper top bar over the working area.
/// - Narrow: a top bar carrying a hamburger, with the same ink sidebar
///   behind a drawer. A bottom bar was tried and withdrawn: it left inner
///   screens with no navigation at all, and the coordinator's destination
///   list overflows five slots, so it could never hold them all.
///
/// A back control appears in the top bar whenever the location is below a
/// destination or owned by none, on every width. On narrow it sits beside
/// the hamburger rather than replacing it, so a reader on an inner page is
/// never one back-tap away from losing navigation.
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

  /// Below this width the sidebar gives way to bottom navigation.
  static const double railBreakpoint = 720;

  /// At and above this width the sidebar may show labels, and the reader may
  /// collapse it. Below it the rail is icons-only and the collapse control is
  /// withheld, because there is nothing to collapse to.
  ///
  /// 900, not 1200: a ~1000 px window is an ordinary laptop or split-screen
  /// size, and pinning the threshold above it left those readers with an
  /// icon rail they could not expand at all.
  static const double fullSidebarFrom = 900;

  static const int minDestinations = 2;

  static const double expandedRailWidth = 256;
  static const double collapsedRailWidth = 76;

  final AsyncValue<List<ShellDestination>> destinations;
  final String location;
  final Widget child;
  final String title;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Widget? accountFooter;

  /// True on the app's designated dead end (`/no-profile`), where a back
  /// control could only bounce straight back.
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
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedPref = ref.watch(sidebarExpandedProvider);
    final loading = destinations.isLoading && !destinations.hasValue;
    final list = destinations.valueOrNull ?? const <ShellDestination>[];

    final showNav = !loading && list.length >= minDestinations;
    final deep = !loading &&
        !suppressBackControl &&
        isDeeperThanDestination(list, location);
    final owner = loading ? null : destinationForLocation(list, location);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= railBreakpoint;
        final canExpand = width >= fullSidebarFrom;
        final collapsed = !(canExpand && expandedPref);

        // Narrow keeps navigation behind a drawer rather than in a bottom
        // bar. A bottom bar left an inner screen with no navigation at all,
        // and this app's longest role (coordinator) overflows five slots, so
        // the bar could not hold every destination anyway.
        final narrowMenu = !wide && (loading || showNav);

        final topBar = _TopBar(
          title: title,
          parent: deep && owner != null && owner.route != location
              ? owner.label
              : null,
          showBack: deep,
          onBack: () => _back(context),
          trailing: trailing,
          showBrand: !wide && !narrowMenu,
          showMenu: narrowMenu,
        );

        // The top bar above the page, in the one shape all three layouts
        // use.
        //
        // The bar is a hard 60px and a Column hands its non-flex children an
        // unbounded main axis, so the bar asks for 60 however little there
        // is — and any viewport shorter than that overflows and stripes the
        // screen. Flutter web hands the app a near-zero canvas for a frame
        // or two before the browser settles its size, and a desktop window
        // can be dragged shorter at any time.
        //
        // The bar keeps its natural height inside an OverflowBox, so it
        // never lays out against an impossible constraint and pushes the
        // overflow inside itself; the SizedBox caps what the Column is asked
        // for, and the ClipRect throws away what does not fit. Nothing
        // readable fits in a viewport this small — the point is only that
        // the shell yields quietly instead of raising.
        Widget barAndBody() {
          final barHeight = math.min(_TopBar.height, constraints.maxHeight);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRect(
                child: SizedBox(
                  height: barHeight,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: _TopBar.height,
                    child: topBar,
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          );
        }

        Widget narrowScaffold(Widget drawerContent) {
          return Scaffold(
            drawer: Drawer(
              width: expandedRailWidth,
              backgroundColor: Palette.of(context).sidebar,
              child: drawerContent,
            ),
            body: SafeArea(bottom: false, child: barAndBody()),
          );
        }

        if (wide && (loading || showNav)) {
          return Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  loading: loading,
                  destinations: list,
                  selected: owner,
                  collapsed: collapsed,
                  canExpand: canExpand,
                  onToggle: () =>
                      ref.read(sidebarExpandedProvider.notifier).toggle(),
                  onSelect: (d) => _navigate(context, d.route),
                  footer: accountFooter,
                ),
                Expanded(child: barAndBody()),
              ],
            ),
          );
        }

        // Narrow while the role is still resolving: the drawer holds the
        // same inert skeleton the sidebar shows, so the reader can see
        // navigation is coming rather than finding an empty drawer.
        if (narrowMenu && loading) {
          return narrowScaffold(
            const SafeArea(child: _SidebarSkeleton(collapsed: false)),
          );
        }

        if (!showNav) {
          return Scaffold(
            body: SafeArea(bottom: false, child: barAndBody()),
          );
        }

        // Narrow with navigation: the same ink sidebar the wide layout
        // uses, behind the drawer. Selecting closes the drawer before
        // navigating — one left open over the page you just asked for is
        // the bug this guards against.
        return narrowScaffold(
          _Sidebar(
            loading: false,
            destinations: list,
            selected: owner,
            collapsed: false,
            canExpand: false,
            onToggle: () {},
            onSelect: (d) {
              Navigator.of(context).pop();
              _navigate(context, d.route);
            },
            footer: accountFooter,
          ),
        );
      },
    );
  }

}

class _TopBar extends StatelessWidget {
  /// The bar's fixed height. Named because the shell has to cap the bar
  /// against it when the viewport is shorter than the bar itself.
  static const double height = 60;

  const _TopBar({
    required this.title,
    required this.parent,
    required this.showBack,
    required this.onBack,
    required this.trailing,
    required this.showBrand,
    required this.showMenu,
  });

  final String title;
  final String? parent;
  final bool showBack;
  final VoidCallback onBack;
  final Widget? trailing;
  final bool showBrand;

  /// The narrow-width drawer control. It sits in the leading slot and the
  /// back control sits beside it rather than replacing it: a reader on a
  /// deep page must never be one back-tap away from losing navigation.
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;

    return Material(
      color: p.paper,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm + 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.rule)),
        ),
        child: Row(
          children: [
            if (showMenu)
              Builder(
                builder: (context) => IconButton(
                  key: const Key('shellMenu'),
                  tooltip: 'Destinations and account',
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            if (showBack)
              IconButton(
                key: const Key('shellBack'),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
              )
            else if (showBrand)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppTokens.sm),
                child: BrandEmblem(size: 28),
              )
            else
              const SizedBox(width: AppTokens.sm + 4),
            const SizedBox(width: AppTokens.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Row(
                  children: [
                    if (parent != null) ...[
                      Flexible(
                        child: Text(
                          parent!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: p.muted),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 18, color: p.muted),
                      ),
                    ],
                    Flexible(
                      flex: 2,
                      child: Text(
                        title,
                        key: const Key('shellTitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.loading,
    required this.destinations,
    required this.selected,
    required this.collapsed,
    required this.canExpand,
    required this.onToggle,
    required this.onSelect,
    required this.footer,
  });

  final bool loading;
  final List<ShellDestination> destinations;
  final ShellDestination? selected;
  final bool collapsed;
  final bool canExpand;
  final VoidCallback onToggle;
  final ValueChanged<ShellDestination> onSelect;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final width =
        collapsed ? AppShell.collapsedRailWidth : AppShell.expandedRailWidth;

    return AnimatedContainer(
      // The shell's one navigation surface, at every width: the wide
      // layout's rail and the narrow layout's drawer contents are this same
      // widget. Keyed so a test can find the sidebar and measure it —
      // collapsed and expanded differ by width, which is what "collapsed"
      // visually means now that there is no `NavigationRail.extended` flag.
      key: const Key('shellSidebar'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      color: p.sidebar,
      child: SafeArea(
        right: false,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand block. Also the collapse control: tapping it
                // toggles the sidebar wherever labels are allowed.
                _BrandHeader(
                  collapsed: collapsed,
                  canExpand: canExpand,
                  onToggle: onToggle,
                ),
                Divider(height: 1, color: p.sidebarRule),
                const SizedBox(height: AppTokens.sm + 4),
                Expanded(
                  // The empty space below the destinations is itself a
                  // collapse control, so the whole sidebar body is a target
                  // rather than just the 8px edge strip. Translucent, and an
                  // ancestor of the destinations' own InkWells: for a simple
                  // tap the descendant recognizer wins the gesture arena, so
                  // tapping a destination navigates and does NOT also
                  // toggle. Only offered where collapsing means something —
                  // in the narrow drawer the sidebar is always expanded.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: canExpand ? onToggle : null,
                    child: loading
                      ? _SidebarSkeleton(collapsed: collapsed)
                      : ListView(
                          padding: EdgeInsets.symmetric(
                            horizontal:
                                collapsed ? AppTokens.sm + 4 : AppTokens.md - 4,
                          ),
                          children: [
                            // Keyed by route, so when the faculty mode
                            // swaps Advisees for Panels the slot fades
                            // between them instead of snapping.
                            for (final d in destinations)
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                transitionBuilder: (child, a) =>
                                    FadeTransition(opacity: a, child: child),
                                child: _NavItem(
                                  key: ValueKey(d.route),
                                  destination: d,
                                  selected: d == selected,
                                  collapsed: collapsed,
                                  onTap: () => onSelect(d),
                                ),
                              ),
                          ],
                        ),
                  ),
                ),
                if (footer != null) ...[
                  Divider(height: 1, color: p.sidebarRule),
                  ShellPlacement(
                    inSidebar: true,
                    collapsed: collapsed,
                    child: footer!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final ShellDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final fg = selected ? Colors.white : p.sidebarMuted;

    Widget item = Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? AppTokens.sealDark.withValues(alpha: 0.20)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('nav-${destination.route}'),
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          focusColor: AppTokens.sealDark.withValues(alpha: 0.30),
          splashColor: Colors.white.withValues(alpha: 0.08),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (!collapsed)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 3,
                    height: selected ? 20 : 0,
                    margin: const EdgeInsets.only(right: AppTokens.sm + 2),
                    decoration: BoxDecoration(
                      color: AppTokens.sealDark,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Icon(destination.icon, size: 21, color: fg),
                if (!collapsed) ...[
                  const SizedBox(width: AppTokens.md - 4),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(
                        color: selected ? Colors.white : p.sidebarText,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (collapsed) {
      item = Tooltip(
        message: destination.label,
        preferBelow: false,
        child: item,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: item,
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.collapsed,
    required this.canExpand,
    required this.onToggle,
  });

  final bool collapsed;
  final bool canExpand;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;

    final content = SizedBox(
      height: 72,
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (!collapsed) const SizedBox(width: AppTokens.lg - 4),
          BrandEmblem(size: 34, background: p.seal),
          if (!collapsed) ...[
            const SizedBox(width: AppTokens.sm + 4),
            Expanded(
              child: Text(
                'eThesisHub',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: text.titleMedium?.copyWith(
                  color: p.sidebarText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (canExpand)
              Padding(
                padding: const EdgeInsets.only(right: AppTokens.md),
                child: Icon(
                  Icons.keyboard_double_arrow_left_rounded,
                  size: 18,
                  color: p.sidebarMuted,
                ),
              ),
          ],
        ],
      ),
    );

    // Below the expanded breakpoint the rail cannot show labels, so the
    // header is plain branding there.
    if (!canExpand) return content;

    final label = collapsed ? 'Expand sidebar' : 'Collapse sidebar';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('sidebarEdgeToggle'),
            onTap: onToggle,
            hoverColor: Colors.white.withValues(alpha: 0.06),
            splashColor: Colors.white.withValues(alpha: 0.08),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Inert rows while the account's destinations are unknown. A skeleton
/// cannot misroute; a guessed role can offer a destination the account
/// does not hold.
class _SidebarSkeleton extends StatelessWidget {
  const _SidebarSkeleton({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      key: const Key('shellSkeleton'),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.md),
      child: Shimmer(child: Column(
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              height: 16,
              width: collapsed ? 28 : double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: p.sidebarRule,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      )),
    );
  }
}

