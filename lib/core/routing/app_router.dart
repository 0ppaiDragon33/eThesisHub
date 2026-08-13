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

/// Home route for each account role.
String homeRouteFor(UserRole role) => switch (role) {
      UserRole.student => '/student',
      UserRole.faculty => '/faculty',
      UserRole.coordinator => '/coordinator',
      UserRole.dean => '/dean',
    };

final goRouterProvider = Provider<GoRouter>((ref) {
  // Watch the auth providers so GoRouter knows to re-evaluate redirects when they change
  ref.watch(authStateProvider);
  ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final authState = ref.read(authStateProvider).value;
      final location = state.matchedLocation;
      final onAuthScreen = location == '/login' || location == '/register';

      if (authState == null) {
        return onAuthScreen ? null : '/login';
      }
      if (!authState.emailVerified) {
        return location == '/verify-email' ? null : '/verify-email';
      }

      final profile = ref.read(currentUserProvider).value;
      if (profile == null) return null; // still loading

      final home = homeRouteFor(profile.role);
      if (onAuthScreen || location == '/verify-email') return home;

      // Prevent reaching another role's dashboard by typing its URL.
      const dashboards = ['/student', '/faculty', '/coordinator', '/dean'];
      if (dashboards.contains(location) && location != home) return home;

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const VerifyEmailScreen(),
      ),
      GoRoute(path: '/student', builder: (_, __) => const StudentDashboard()),
      GoRoute(path: '/faculty', builder: (_, __) => const FacultyDashboard()),
      GoRoute(
        path: '/coordinator',
        builder: (_, __) => const CoordinatorDashboard(),
      ),
      GoRoute(path: '/dean', builder: (_, __) => const DeanDashboard()),
    ],
  );
});
