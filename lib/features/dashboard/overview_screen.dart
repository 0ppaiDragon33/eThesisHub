import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/coordinator_overview.dart';
import 'package:ethesishub/features/dashboard/dean_overview.dart';
import 'package:ethesishub/features/dashboard/faculty_overview.dart';
import 'package:ethesishub/features/dashboard/student_overview.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Index 0 on every dashboard: which overview to show, decided by the
/// signed-in user's role.
///
/// Deliberately does not default a role (spec D25). An unknown or
/// not-yet-resolved role renders nothing at all rather than falling
/// through to a student's view -- the router's `/no-profile` redirect is
/// what a reader with no role lands on, and this widget must never race it
/// with a guessed dashboard.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider).valueOrNull?.role;
    return KeyedSubtree(
      key: const Key('overviewScreen'),
      child: switch (role) {
        UserRole.student => const StudentOverview(),
        UserRole.faculty => const FacultyOverview(),
        UserRole.dean => const DeanOverview(),
        UserRole.coordinator => const CoordinatorOverview(),
        null => const SizedBox.shrink(),
      },
    );
  }
}
