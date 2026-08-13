import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/features/auth/register_screen.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/features/dashboard/coordinator_dashboard.dart';
import 'package:ethesishub/features/dashboard/dean_dashboard.dart';
import 'package:ethesishub/features/dashboard/faculty_dashboard.dart';
import 'package:ethesishub/features/dashboard/student_dashboard.dart';
import 'package:ethesishub/providers/auth_providers.dart';

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
    ],
  );
});
