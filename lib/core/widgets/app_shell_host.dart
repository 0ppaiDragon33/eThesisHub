import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/app_shell.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/faculty_mode_switch.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/notification_providers.dart';
import 'package:ethesishub/providers/shell_providers.dart';
import 'package:ethesishub/providers/sidebar_provider.dart';
import 'package:ethesishub/providers/theme_provider.dart';

/// What the app bar calls the page you are on.
///
/// Every signed-in screen used to carry its own `AppBar` and so its own
/// title; the shell owns the bar now, so the titles live here, keyed by
/// route. Two are computed rather than looked up because the screen's own
/// bar computed them too:
///
/// - the chapter detail title is the chapter's label, which is derivable
///   from the path parameter without waiting on any stream;
/// - the review queue is named for the decision it asks for, which differs
///   between the Dean (approve) and the Coordinator (recommend).
///
/// A route with no entry falls back to the app's name rather than to an
/// empty bar — a bar with no words in it still leaves the reader unsure
/// where they are, which is the complaint this milestone answers.
String shellTitleFor(
  String location,
  Map<String, String> pathParameters,
  UserRole? role,
) {
  if (location.startsWith('/thesis/chapters/')) {
    final chapter = ChapterId.fromString(pathParameters['chapterId']);
    // Null by design for an id that is not one of the five chapters. The
    // route builder renders its own "No such chapter" refusal for that
    // case; naming the bar 'Chapter' keeps that refusal somewhere you can
    // read and leave.
    return chapter?.label ?? 'Chapter';
  }
  if (location == '/review') {
    return role == UserRole.dean
        ? 'Nomination approvals'
        : 'Nomination recommendations';
  }

  // The defence routes carry a path parameter, so `matchedLocation` is the
  // resolved path, never the registered pattern — these cannot be looked up
  // in the table below. Ordered most specific first, and '/defence/schedule'
  // is settled before the ':thesisId' catch-all for the same reason the
  // router registers it first: 'schedule' would otherwise read as a thesis
  // id.
  if (location.startsWith('/defence/room/')) {
    return location.endsWith('/consolidated')
        ? 'Consolidated comments'
        : 'Defence room';
  }
  if (location != '/defence/schedule' && location.startsWith('/defence/')) {
    return 'Title defence';
  }

  return _staticTitles[location] ?? 'eThesisHub';
}

/// Static route -> title lookup for [shellTitleFor].
///
/// '/overview' names itself, not the app: spec §5.4 says the bar names the
/// screen you are on, and 'eThesisHub' on the one destination every role
/// lands on first said the opposite -- the sidebar's own label for it is
/// 'Overview' (see `shell_destination.dart`), so the two disagreed about
/// what to call the same screen.
const _staticTitles = {
  '/overview': 'Overview',
  '/defences': 'Defences',
  '/advisees': 'Advisees',
  '/panels': 'Panels',
  '/approvals': 'Approvals',
  '/recommendations': 'Recommendations',
  '/title-defences': 'Title defences',
  '/readiness': 'Readiness',
  '/no-profile': 'Profile unavailable',
  '/thesis': 'My thesis',
  '/thesis/create': 'Create thesis group',
  '/thesis/nominate': 'Nominate adviser and panel',
  '/thesis/titles': 'Candidate titles',
  '/thesis/chapters': 'Chapters',
  '/defence/schedule': 'Schedule a defence',
  '/nominations': 'Nomination inbox',
  '/invites': 'Invites',
  '/users': 'Users',
};

/// Wires [AppShell] to this app's providers and router.
///
/// [AppShell] itself takes its destinations and location as plain
/// parameters so every case in it can be tested without building a
/// `GoRouter`. This is the one place that knows about both, and it is
/// deliberately thin: everything it does is either read a provider or
/// call `context.go`.
class AppShellHost extends ConsumerWidget {
  const AppShellHost({
    super.key,
    required this.location,
    required this.pathParameters,
    required this.child,
  });

  final String location;
  final Map<String, String> pathParameters;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationDetectorsProvider);
    final destinations = ref.watch(shellDestinationsProvider);
    final role = ref.watch(currentUserProvider).valueOrNull?.role;
    final list = destinations.valueOrNull ?? const <ShellDestination>[];

    return AppShell(
      destinations: destinations,
      location: location,
      title: shellTitleFor(location, pathParameters, role),
      // The mode switch is faculty-only and hides itself further when the
      // member holds no adviser position. Passing it for other roles would
      // start two position-count queries they have no rules arm for.
      trailing:
          role == UserRole.faculty ? FacultyModeSwitch(location: location) : null,
      // Name, role and sign-out at the foot of the sidebar (spec §5.3),
      // where it used to be a bare `SignOutButton` repeated in four
      // dashboards' app bars with no identity shown anywhere but the
      // '/overview' greeting.
      accountFooter: const AccountFooter(),
      // '/no-profile' is this milestone's designated dead end: no
      // destination owns it (the sidebar is empty for an unknown role, by
      // design), so `isDeeperThanDestination` always answers true there
      // and a back control would render -- but `_back` below always falls
      // through to the same '/overview' redirect that immediately bounces
      // back to '/no-profile', so tapping it does nothing. A control that
      // does nothing on the app's own dead-end screen is exactly what this
      // milestone exists to remove, so it is suppressed here rather than
      // left to render and fail silently.
      suppressBackControl: location == '/no-profile',
      onBack: () => _back(context, list),
      child: child,
    );
  }

  /// Back, for an app whose navigation is a mix of `context.go` (onto a
  /// destination) and `context.push` (onto a screen below one, per D23).
  ///
  /// A pushed screen has a real Navigator entry beneath it, so `canPop`
  /// answers true and a plain pop is correct and sufficient -- see below.
  /// This structural fallback exists for what a pop cannot handle: a deep
  /// screen reached directly by URL (a bookmark, a refresh, a shared link)
  /// has nothing beneath it in THIS Navigator to pop to, so it rises to
  /// the destination that owns this location instead, or to the overview
  /// when none does.
  void _back(BuildContext context, List<ShellDestination> destinations) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final owner = destinationForLocation(destinations, location);
    if (owner != null && location != owner.route) {
      context.go(owner.route);
      return;
    }
    context.go('/overview');
  }
}

/// A role's label for [AccountFooter]. Local to display, not [UserRole]
/// itself -- D25 governs what the app DOES with an unknown role (nothing
/// silently defaulted), not what a resolved one is called on screen.
String _roleLabel(UserRole role) => switch (role) {
      UserRole.student => 'Student',
      UserRole.faculty => 'Faculty',
      UserRole.coordinator => 'College Research Coordinator',
      UserRole.dean => 'Dean',
    };

/// Name, role and sign-out at the foot of the sidebar (spec §5.3).
///
/// Watches [currentUserProvider] itself rather than trusting whatever
/// already gated the shell into rendering: the one account this footer
/// MUST still work for is exactly the one whose `users/{uid}` document is
/// missing or unreadable -- the `/no-profile` case -- because that reader
/// has no destination to reach and no other account to switch to, so
/// sign-out is the one control that may never depend on the profile read
/// that just failed. A missing or errored profile therefore degrades to
/// sign-out alone, never a blank footer and never a thrown error.
class AccountFooter extends ConsumerWidget {
  const AccountFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider).valueOrNull;

    if (profile == null) {
      // Degraded state (spec: no code path may depend on `users/{uid}`
      // existing to render the shell at all) -- sign-out and the theme
      // toggle both still work here, since neither reads the profile.
      return const Padding(
        key: Key('accountFooterSignOutOnly'),
        padding: EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SignOutButton(),
            _ThemeToggleButton(),
          ],
        ),
      );
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    // Same `Key('accountFooter')` widget renders in two places that behave
    // very differently: `NavigationDrawer` lays its children out inside a
    // plain `ListView`, which genuinely bounds their width to the drawer's
    // own -- an `Expanded` there is safe. `NavigationRail`'s `trailing`
    // slot does NOT: `NavigationRail` sizes itself from an
    // `IntrinsicWidth`-style probe of its content with no `maxWidth` cap,
    // so its trailing child is laid out with a genuinely UNBOUNDED width
    // constraint. An `Expanded` there throws ("RenderFlex children have
    // non-zero flex but incoming width constraints are unbounded"), and
    // before that, a bare `Flexible` inside a min-size `Row` just rendered
    // the name at its full natural width -- unbounded, so it never
    // wrapped or ellipsized -- which is the overflow this fixes.
    //
    // `wide` mirrors `AppShell.railBreakpoint`: when the shell would be
    // showing the rail (not the drawer), this footer self-imposes the
    // rail's own width -- 220 expanded, 72 collapsed -- so `Expanded`
    // below finally has something finite to divide. A collapsed 72px
    // rail cannot fit a name, a role, AND two icon buttons, so that case
    // drops to icons only, the same trade `NavigationRail` itself makes
    // for destination labels when collapsed.
    final wide = MediaQuery.sizeOf(context).width >= AppShell.railBreakpoint;
    final expanded = wide ? ref.watch(sidebarExpandedProvider) : true;

    if (wide && !expanded) {
      return const Padding(
        key: Key('accountFooter'),
        padding: EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThemeToggleButton(),
            SignOutButton(),
          ],
        ),
      );
    }

    Widget footer = Padding(
      key: const Key('accountFooter'),
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.fullName,
                  key: const Key('accountFooterName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dark ? AppTokens.inkDark : AppTokens.ink,
                  ),
                ),
                Text(
                  _roleLabel(profile.role),
                  key: const Key('accountFooterRole'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          // Sign-out and the theme toggle in their own column, separate
          // from the name/role column above -- two icon-sized controls
          // side by side would not fit the 220px rail alongside a long
          // name, but stacked they always do.
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThemeToggleButton(),
              SignOutButton(),
            ],
          ),
        ],
      ),
    );

    if (wide) {
      footer = SizedBox(width: AppShell.expandedRailWidth, child: footer);
    }
    return footer;
  }
}

/// Cycles [themeModeProvider] system -> light -> dark -> system.
///
/// The icon and tooltip both name the *next* state, not the current one --
/// this is a control you press to get somewhere, not a status readout.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final (icon, tooltip) = switch (mode) {
      ThemeMode.system => (Icons.light_mode_outlined, 'Switch to light theme'),
      ThemeMode.light => (Icons.dark_mode_outlined, 'Switch to dark theme'),
      ThemeMode.dark => (Icons.brightness_auto_outlined, 'Switch to system theme'),
    };

    return IconButton(
      key: const Key('themeToggle'),
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
    );
  }
}
