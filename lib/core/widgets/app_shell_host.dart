import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/app_shell.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/faculty_mode_switch.dart';
import 'package:ethesishub/features/notifications/notification_bell.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/notification_providers.dart';
import 'package:ethesishub/providers/shell_providers.dart';
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

  if (location != '/archive/queue' && location.startsWith('/archive/')) {
    return 'Archive record';
  }

  // A saved form copy, '/forms/<formId>/copies/<copyId>'. The copy's own
  // name is on the page; the bar says what kind of page this is. Matched
  // specifically so a future '/forms/...' route that is not the editor
  // does not also pick up this title.
  if (location.startsWith('/forms/') && location.contains('/copies/')) {
    return 'Edit form';
  }

  return _staticTitles[location] ?? 'eThesisHub';
}

/// Static route -> title lookup for [shellTitleFor].
///
/// '/overview' names itself, not the app: spec §5.4 says the bar names the
/// screen you are on, and 'eThesisHub' on the one destination every role
/// lands on first said the opposite -- the sidebar's own label for it is
/// 'Dashboard' (see `shell_destination.dart`), so the two must agree about
/// what to call the same screen.
const _staticTitles = {
  '/overview': 'Dashboard',
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
  '/audit': 'Activity log',
  '/stalled': 'Stalled nominations',
  '/notifications': 'Notifications',
  '/archive': 'Archive',
  '/archive/queue': 'Publish to archive',
  '/forms': 'Forms',
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NotificationBell(),
          if (role == UserRole.faculty) FacultyModeSwitch(location: location),
        ],
      ),
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

/// Who is signed in, the theme control, and sign-out.
///
/// Drawn in three places, told which by [ShellPlacement]: the full ink
/// sidebar, the collapsed icon sidebar, and the phone's "More" sheet.
///
/// Watches [currentUserProvider] itself: the one account this footer must
/// still serve is the one whose profile is missing, so a missing or failed
/// profile degrades to the two controls alone — never a blank footer and
/// never a thrown error.
class AccountFooter extends ConsumerWidget {
  const AccountFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider).valueOrNull;
    final placement = ShellPlacement.maybeOf(context);
    final inSidebar = placement?.inSidebar ?? false;
    final collapsed = placement?.collapsed ?? false;
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;

    final controls = IconTheme.merge(
      data: IconThemeData(color: inSidebar ? p.sidebarMuted : p.muted),
      child: Flex(
        direction: collapsed ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThemeToggleButton(onDark: inSidebar),
          _SidebarSignOut(onDark: inSidebar),
        ],
      ),
    );

    if (profile == null) {
      return Padding(
        key: const Key('accountFooterSignOutOnly'),
        padding: const EdgeInsets.all(AppTokens.sm),
        child: Align(
          alignment: collapsed ? Alignment.center : Alignment.centerLeft,
          child: controls,
        ),
      );
    }

    if (collapsed) {
      return Padding(
        key: const Key('accountFooter'),
        padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '${profile.fullName} · ${roleLabel(profile.role)}',
              child: InitialsAvatar(profile.fullName, size: 34),
            ),
            const SizedBox(height: AppTokens.xs),
            controls,
          ],
        ),
      );
    }

    final nameColor = inSidebar ? p.sidebarText : p.text;
    final roleColor = inSidebar ? p.sidebarMuted : p.muted;

    return Padding(
      key: const Key('accountFooter'),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.md,
        AppTokens.md - 4,
        AppTokens.xs,
        AppTokens.md - 4,
      ),
      child: Row(
        children: [
          InitialsAvatar(profile.fullName, size: 36),
          const SizedBox(width: AppTokens.sm + 2),
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
                  style: text.labelLarge?.copyWith(color: nameColor),
                ),
                Text(
                  roleLabel(profile.role),
                  key: const Key('accountFooterRole'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: roleColor),
                ),
              ],
            ),
          ),
          controls,
        ],
      ),
    );
  }
}

/// [SignOutButton], tinted for the dark sidebar when it sits there.
class _SidebarSignOut extends StatelessWidget {
  const _SidebarSignOut({required this.onDark});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (!onDark) return const SignOutButton();
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Palette.of(context).sidebarMuted,
          hoverColor: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: const SignOutButton(),
    );
  }
}

/// Cycles [themeModeProvider] system -> light -> dark -> system.
///
/// The icon and tooltip both name the *next* state: this is a control you
/// press to get somewhere, not a status readout.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton({required this.onDark});

  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final (icon, tooltip) = switch (mode) {
      ThemeMode.system => (Icons.light_mode_outlined, 'Switch to light theme'),
      ThemeMode.light => (Icons.dark_mode_outlined, 'Switch to dark theme'),
      ThemeMode.dark => (
        Icons.brightness_auto_outlined,
        'Switch to system theme',
      ),
    };

    return IconButton(
      key: const Key('themeToggle'),
      icon: Icon(icon),
      tooltip: tooltip,
      color: onDark ? Palette.of(context).sidebarMuted : null,
      hoverColor: onDark ? Colors.white.withValues(alpha: 0.08) : null,
      onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
    );
  }
}
