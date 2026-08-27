import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/coordinator_overview.dart';
import 'package:ethesishub/features/dashboard/dean_overview.dart';
import 'package:ethesishub/features/dashboard/faculty_overview.dart';
import 'package:ethesishub/features/dashboard/student_overview.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// What `/overview` shows: which overview to render, decided by the
/// signed-in account's role.
///
/// Deliberately does not default a role (spec D25). This project has twice
/// shipped software that quietly chose one — a group leader's upload button
/// permanently hidden, a dean silently routed down the faculty code path —
/// and both times it looked like it was working.
///
/// It is just as important that "not yet known" is not treated as
/// "unknown". This screen used to read `.valueOrNull?.role` and render
/// `SizedBox.shrink()` for null, which is true BOTH while
/// `currentUserProvider` is still loading AND when the profile document is
/// genuinely absent — so a perfectly ordinary first paint was
/// indistinguishable from a broken account, and rendered the same nothing.
/// The three cases are now kept apart:
///
/// - **loading**: a real loading state. The role is arriving; nobody has
///   been diagnosed with anything.
/// - **settled and known**: that role's overview.
/// - **settled and unknown** (the document is absent, or the read failed):
///   nothing at all, and the router's redirect — which re-fires on exactly
///   this change — is what carries the reader to `/no-profile`, where the
///   two causes are named apart and Retry and Sign out are offered. Nothing
///   here guesses a role to fill the gap in the meantime.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProvider);

    return KeyedSubtree(
      key: const Key('overviewScreen'),
      child: profileAsync.when(
        loading: () => const LoadingState(label: 'Loading your overview…'),
        // Settled, and the answer is "no role". Same as an absent document
        // as far as this screen is concerned: it has nothing to render and
        // will not invent something. /no-profile explains the difference
        // between the two, because that is where the difference matters.
        error: (_, _) => const SizedBox.shrink(),
        data: (profile) => switch (profile?.role) {
          UserRole.student => const StudentOverview(),
          UserRole.faculty => const FacultyOverview(),
          UserRole.dean => const DeanOverview(),
          UserRole.coordinator => const CoordinatorOverview(),
          null => const SizedBox.shrink(),
        },
      ),
    );
  }
}
