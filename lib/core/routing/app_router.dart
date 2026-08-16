import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/features/auth/register_screen.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/features/dashboard/coordinator_dashboard.dart';
import 'package:ethesishub/features/dashboard/dean_dashboard.dart';
import 'package:ethesishub/features/dashboard/faculty_dashboard.dart';
import 'package:ethesishub/features/dashboard/student_dashboard.dart';
import 'package:ethesishub/features/nomination/nomination_inbox_screen.dart';
import 'package:ethesishub/features/nomination/review_queue_screen.dart';
import 'package:ethesishub/features/thesis/create_thesis_screen.dart';
import 'package:ethesishub/features/thesis/nominate_screen.dart';
import 'package:ethesishub/features/thesis/thesis_status_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Simple ChangeNotifier that allows external code to trigger notifications.
class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Home route for each account role.
String homeRouteFor(UserRole role) => switch (role) {
      UserRole.student => '/student',
      UserRole.faculty => '/faculty',
      UserRole.coordinator => '/coordinator',
      UserRole.dean => '/dean',
    };

final goRouterProvider = Provider<GoRouter>((ref) {
  // Build the router once. Use a ChangeNotifier with ref.listen to re-evaluate
  // redirects when auth state changes, avoiding router reconstruction which would
  // drop navigation state. The redirect callback uses ref.read to get current values.
  final refreshNotifier = _RouterRefreshNotifier();

  ref.listen(authStateProvider, (_, _) {
    refreshNotifier.notify();
  });

  ref.listen(currentUserProvider, (_, _) {
    refreshNotifier.notify();
  });

  // Needed so the `/thesis/nominate` bare-visit fallback (below) gets a
  // second chance to redirect once the leader's thesis has actually loaded
  // — the first redirect evaluation can land before this stream's first
  // event arrives, same class of race documented on authStateProvider.
  ref.listen(myThesisProvider, (_, _) {
    refreshNotifier.notify();
  });

  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authStateAsync = ref.read(authStateProvider);
      final location = state.matchedLocation;
      final onAuthScreen = location == '/login' || location == '/register';

      // Distinguish loading from signed-out. While loading, stay put rather than
      // routing to login. Only a settled null means the user is signed out.
      return authStateAsync.when(
        data: (authState) {
          if (authState == null) {
            return onAuthScreen ? null : '/login';
          }
          if (!authState.emailVerified) {
            return location == '/verify-email' ? null : '/verify-email';
          }

          final profileAsync = ref.read(currentUserProvider);
          return profileAsync.when(
            data: (profile) {
              // currentUserProvider is a StreamProvider, and AsyncLoading
              // already covers the "still loading" case (handled below). A
              // settled `data(null)` here means the users/{uid} document
              // does not exist for this signed-in, verified account (e.g.
              // it was never created, or was removed). Send them to /login,
              // which shows a "signed in as X — sign out" affordance so
              // they aren't stuck with no error and no escape.
              if (profile == null) {
                return onAuthScreen ? null : '/login';
              }

              final home = homeRouteFor(profile.role);
              if (onAuthScreen || location == '/verify-email') return home;

              // Prevent reaching another role's dashboard by typing its URL.
              final userDashboards =
                  UserRole.values.map(homeRouteFor).toList();
              if (userDashboards.contains(location) && location != home) {
                return home;
              }

              // M1a screens are role-scoped. A wrong-role user goes to their
              // own home rather than seeing an empty or forbidden screen.
              // This is a UX guard only — the real authorization boundary is
              // firestore.rules, which every screen's writes and reads still
              // go through regardless of what the client permits.
              const studentOnly = ['/thesis', '/thesis/create', '/thesis/nominate'];
              if (studentOnly.any(location.startsWith) &&
                  profile.role != UserRole.student) {
                return home;
              }
              // Open to faculty, coordinators and deans — a coordinator or
              // dean nominated as a panel member on someone else's thesis
              // still needs their own inbox.
              if (location.startsWith('/nominations') &&
                  profile.role == UserRole.student) {
                return home;
              }
              if (location.startsWith('/review') &&
                  profile.role != UserRole.coordinator &&
                  profile.role != UserRole.dean) {
                return home;
              }

              // '/thesis/nominate' reads its thesis id from a required
              // query parameter. A bare visit (typed directly, or reached
              // with no thesis context) falls back to the signed-in
              // leader's own thesis rather than crashing on the route
              // builder's null-check; a leader with no thesis yet is sent
              // to create one first.
              if (location.startsWith('/thesis/nominate') &&
                  state.uri.queryParameters['id'] == null) {
                // Distinguish "still loading" from "has no thesis" — reading
                // `.valueOrNull` here would treat an unsettled stream the
                // same as a settled `null`, misrouting a leader who genuinely
                // has a thesis to /thesis/create on first load (this bites
                // on Web, where a page reload re-runs this redirect before
                // myThesisProvider's first snapshot has arrived; in-app
                // navigation never sees it because the provider is already
                // warm by then). While loading, hold here (no redirect) —
                // the route builder below renders a brief loading state for
                // the bare-visit case, and the `ref.listen(myThesisProvider)`
                // above re-triggers this same redirect, at this same
                // location, once the stream settles.
                final myThesisAsync = ref.read(myThesisProvider);
                return myThesisAsync.when(
                  data: (myThesis) => myThesis == null
                      ? '/thesis/create'
                      : '/thesis/nominate?id=${myThesis.id}',
                  loading: () => null,
                  error: (_, _) => '/thesis/create',
                );
              }

              return null;
            },
            loading: () => null, // still loading profile, stay put
            error: (_, _) => null,
          );
        },
        loading: () => null, // still loading auth, stay put
        error: (_, _) => onAuthScreen ? null : '/login',
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      GoRoute(path: '/student', builder: (_, _) => const StudentDashboard()),
      GoRoute(path: '/faculty', builder: (_, _) => const FacultyDashboard()),
      GoRoute(
        path: '/coordinator',
        builder: (_, _) => const CoordinatorDashboard(),
      ),
      GoRoute(path: '/dean', builder: (_, _) => const DeanDashboard()),
      GoRoute(
        path: '/thesis/create',
        builder: (_, _) => const CreateThesisScreen(),
      ),
      GoRoute(
        path: '/thesis',
        builder: (_, _) => const ThesisStatusScreen(),
      ),
      GoRoute(
        path: '/thesis/nominate',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          if (id == null) {
            // Bare visit while the redirect above is still waiting on
            // myThesisProvider's first snapshot (see the redirect callback
            // for why it does not commit to a destination yet). Brief and
            // self-resolving: the moment that provider settles, the
            // refreshListenable fires and the redirect sends us to
            // /thesis/create or /thesis/nominate?id=... as appropriate.
            return const Scaffold(
              key: Key('nominateBareVisitLoading'),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return NominateScreen(thesisId: id);
        },
      ),
      GoRoute(
        path: '/nominations',
        builder: (_, _) => const NominationInboxScreen(),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) {
          final profile = ref.read(currentUserProvider).value;
          final isDean = profile?.role == UserRole.dean;
          return ReviewQueueScreen(
            queue: isDean
                ? ThesisStatus.nominationPendingDean
                : ThesisStatus.nominationPendingCoordinator,
            isDean: isDean,
          );
        },
      ),
    ],
  );
});
