import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/widgets/app_shell.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/faculty_mode_switch.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shell_providers.dart';

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

  return const {
    '/overview': 'eThesisHub',
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
    '/invites': 'Faculty',
  }[location] ??
      'eThesisHub';
}

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
      // One sign-out for the whole app, where it used to be repeated in
      // four dashboards' app bars.
      accountFooter: const Padding(
        padding: EdgeInsets.all(8),
        child: SignOutButton(),
      ),
      onBack: () => _back(context, list),
      child: child,
    );
  }

  /// Back, for an app whose every navigation is a `context.go`.
  ///
  /// `go` REPLACES the stack rather than pushing onto it, which is why
  /// Flutter never drew a back arrow here and why a plain `Navigator.pop`
  /// would have nothing to pop. So "back" is answered structurally: rise
  /// to the destination that owns this location, or to the overview when
  /// none does. `canPop` is still consulted first, so a genuine push (a
  /// dialog route, or any future `context.push`) unwinds the way its
  /// reader expects.
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
