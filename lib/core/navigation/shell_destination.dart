import 'package:flutter/material.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/user_role.dart';

/// One place the sidebar can send you, and the routes it speaks for.
///
/// [alsoOwns] exists because highlighting cannot be done by string
/// prefix. '/defences' and '/defence/room/:id' are one character apart
/// and are different screens; a naive `startsWith` lights Defences for
/// the defence room and tells the reader they are somewhere they are
/// not. Ownership is therefore declared, never inferred.
class ShellDestination {
  const ShellDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.alsoOwns = const [],
  });

  final String label;
  final IconData icon;

  /// Where selecting this destination navigates. Always a `context.go`.
  final String route;

  /// Extra route roots this destination speaks for, beyond [route].
  final List<String> alsoOwns;

  /// True when [location] is this destination or sits beneath it.
  ///
  /// A nested match requires the separator — '/thesis/chapters' owns
  /// '/thesis/chapters/chapterIII' but must never own a hypothetical
  /// '/thesis/chaptersArchive', which is a different screen that merely
  /// starts with the same characters.
  bool owns(String location) {
    for (final root in [route, ...alsoOwns]) {
      if (location == root || location.startsWith('$root/')) return true;
    }
    return false;
  }
}

/// The destinations a given role may see, in sidebar order.
///
/// Overview is always first: landing on a work queue was the complaint
/// the previous milestone existed to answer, and it must not creep back.
///
/// Destinations that would lead to a screen refusing the reader are not
/// declared at all. A control that does nothing when tapped reads as a
/// broken app rather than an unfinished one.
List<ShellDestination> destinationsFor({
  required UserRole role,
  bool chaptersUnlocked = false,
  FacultyMode facultyMode = FacultyMode.adviser,
}) {
  const overview = ShellDestination(
    label: 'Overview',
    icon: Icons.dashboard_outlined,
    route: '/overview',
  );
  const defences = ShellDestination(
    label: 'Defences',
    icon: Icons.event_note_outlined,
    route: '/defences',
  );

  return switch (role) {
    UserRole.student => [
        overview,
        const ShellDestination(
          label: 'My thesis',
          icon: Icons.home_outlined,
          route: '/thesis',
        ),
        // Gated on the Dean approving a title, which is when the screens
        // behind them stop refusing.
        if (chaptersUnlocked) ...[
          const ShellDestination(
            label: 'Chapters',
            icon: Icons.menu_book_outlined,
            route: '/thesis/chapters',
          ),
          defences,
        ],
      ],
    UserRole.faculty => [
        overview,
        // One or the other, never both: the mode is the primary axis and
        // each mode is its own clean list (design decision D5).
        if (facultyMode == FacultyMode.adviser)
          const ShellDestination(
            label: 'Advisees',
            icon: Icons.school_outlined,
            route: '/advisees',
          )
        else
          const ShellDestination(
            label: 'Panels',
            icon: Icons.forum_outlined,
            route: '/panels',
          ),
        defences,
        const ShellDestination(
          label: 'Nominations',
          icon: Icons.drafts_outlined,
          route: '/nominations',
        ),
      ],
    UserRole.dean => [
        overview,
        const ShellDestination(
          label: 'Approvals',
          icon: Icons.gavel_outlined,
          route: '/approvals',
        ),
        const ShellDestination(
          label: 'Title defences',
          icon: Icons.forum_outlined,
          route: '/title-defences',
        ),
        defences,
        const ShellDestination(
          label: 'Readiness',
          icon: Icons.checklist_outlined,
          route: '/readiness',
        ),
      ],
    UserRole.coordinator => [
        overview,
        const ShellDestination(
          label: 'Recommendations',
          icon: Icons.fact_check_outlined,
          route: '/recommendations',
        ),
        const ShellDestination(
          label: 'Title defences',
          icon: Icons.forum_outlined,
          route: '/title-defences',
        ),
        defences,
        const ShellDestination(
          label: 'Readiness',
          icon: Icons.checklist_outlined,
          route: '/readiness',
        ),
        const ShellDestination(
          label: 'Faculty',
          icon: Icons.badge_outlined,
          route: '/invites',
        ),
      ],
  };
}

/// The destination that speaks for [location], or null when none does.
///
/// Null is a real answer, not a failure. Highlighting nothing is better
/// than highlighting the wrong thing.
///
/// When multiple destinations own a location, returns the most specific
/// one (the one with the longest route), since nested destinations like
/// '/thesis/chapters' should be preferred over '/thesis'.
ShellDestination? destinationForLocation(
  List<ShellDestination> destinations,
  String location,
) {
  final owners = destinations.where((d) => d.owns(location)).toList();
  if (owners.isEmpty) return null;
  // Prefer the destination with the longest route. Today alsoOwns is
  // always empty, so this sorts by route.length. If a destination ever
  // gains an alsoOwns entry deeper than another destination's bare route,
  // this would pick wrongly (should compare the matched root, not d.route).
  owners.sort((a, b) => b.route.length.compareTo(a.route.length));
  return owners.first;
}

/// True when the shell should offer a back control.
///
/// Two cases: a location nested beneath a destination, and a location no
/// destination owns at all. In both the sidebar alone cannot return the
/// reader where they came from.
bool isDeeperThanDestination(
  List<ShellDestination> destinations,
  String location,
) {
  final owner = destinationForLocation(destinations, location);
  if (owner == null) return true;
  return location != owner.route;
}
