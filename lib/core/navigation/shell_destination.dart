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
  // Nullable: `null` means the member currently holds neither designation
  // nor a position for either mode, and (spec §6) gets neither the Advisees
  // nor the Panels destination at all rather than one that leads to an
  // empty screen.
  FacultyMode? facultyMode = FacultyMode.adviser,
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
  // The one destination not scoped to what the reader is personally
  // involved in: a student browses theses they had nothing to do with,
  // and that is the point (see archive_screen.dart's own doc comment).
  // Every role gets it, unlike everything else on this list.
  const archive = ShellDestination(
    label: 'Archive',
    icon: Icons.local_library_outlined,
    route: '/archive',
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
        archive,
      ],
    UserRole.faculty => [
        overview,
        // One or the other, never both: the mode is the primary axis and
        // each mode is its own clean list (design decision D5). `null`
        // (neither designated nor holding a position for either mode)
        // declares NEITHER destination — not an empty one (spec §6).
        if (facultyMode == FacultyMode.adviser)
          const ShellDestination(
            label: 'Advisees',
            icon: Icons.school_outlined,
            route: '/advisees',
          )
        else if (facultyMode == FacultyMode.panelist)
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
        archive,
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
        archive,
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
          label: 'Users',
          icon: Icons.people_outline,
          route: '/users',
          alsoOwns: ['/invites'],
        ),
        archive,
      ],
  };
}

/// The destination that speaks for [location], or null when none does.
///
/// Null is a real answer, not a failure. Highlighting nothing is better
/// than highlighting the wrong thing.
///
/// When multiple destinations own a location, returns the most specific
/// one -- the one whose matched root (its [ShellDestination.route] or one
/// of its [ShellDestination.alsoOwns] entries) is longest, since nested
/// roots like '/thesis/chapters' should be preferred over '/thesis'.
///
/// Compares the length of the ROOT THAT ACTUALLY MATCHED, never
/// `d.route.length` alone: a destination can own a location only through
/// an `alsoOwns` entry deeper than its own bare route (Users owns
/// '/invites' this way), and sorting by `d.route` would then prefer a
/// shorter, less specific match purely because that destination's own
/// route happened to be a longer string. See
/// `shell_destination_test.dart`'s "the tiebreak compares the matched
/// root" case for the scenario this would get wrong.
ShellDestination? destinationForLocation(
  List<ShellDestination> destinations,
  String location,
) {
  ShellDestination? best;
  var bestRootLength = -1;
  for (final d in destinations) {
    for (final root in [d.route, ...d.alsoOwns]) {
      final matches = location == root || location.startsWith('$root/');
      if (matches && root.length > bestRootLength) {
        bestRootLength = root.length;
        best = d;
      }
    }
  }
  return best;
}

/// True when the shell should offer a back control.
///
/// Two cases: a location nested beneath a destination, and a location no
/// destination owns at all. In both the sidebar alone cannot return the
/// reader where they came from.
///
/// An `alsoOwns` root is NOT one of those cases. `alsoOwns` names a route
/// the destination owns as a PEER of its own -- the Users destination owns
/// '/users' and '/invites' as its two tabs -- not a screen nested beneath
/// it. Comparing against `owner.route` alone made '/invites' answer `true`
/// and drew a back control on a top-level tab, which says "you are one
/// level down" about a place you are not, and points at whatever route the
/// reader happened to visit before rather than at a parent, since there is
/// no parent. Both tabs carry the Accounts/Invites strip, so leaving one is
/// already a tab away and the back control adds nothing but the wrong
/// claim. Matching any of the destination's roots is the same test
/// [destinationForLocation] itself uses to decide ownership, so the two
/// stay consistent.
bool isDeeperThanDestination(
  List<ShellDestination> destinations,
  String location,
) {
  final owner = destinationForLocation(destinations, location);
  if (owner == null) return true;
  return location != owner.route && !owner.alsoOwns.contains(location);
}

/// Whether [route] is a screen below a destination for [role] -- the exact
/// ownership test the shell itself runs to decide the back control (see
/// [isDeeperThanDestination]), applied ahead of time so anything that hands
/// out a route (a needs-you queue, a card's "Open" button) can decide
/// `push` vs `go` from the one definition rather than restating it.
///
/// This is deliberately role-dependent, not a fixed list of "deep routes":
/// '/thesis/chapters' is the Chapters destination itself for a student
/// once chapters are unlocked, so it is NOT deep for one, but no faculty,
/// dean or coordinator destination owns it at all, so the very same route
/// IS deep for those roles. Callers reading a route on behalf of a role
/// that is not its own -- an adviser opening a student's chapters, a
/// coordinator opening one from the readiness list -- always get `true`,
/// which is correct: that reader has no destination to return them to
/// there, so the screen must be pushed to leave a real back stop.
///
/// [route] may carry a query string (`/thesis/chapters?id=t1`); only its
/// path is meaningful to ownership.
///
/// [chaptersUnlocked] and [facultyMode] only change the answer for a
/// student or faculty role respectively, and only for routes under
/// '/thesis' or the Advisees/Panels pair -- they default to the most
/// permissive values because a caller checking a route it just built
/// (inside the branch that proves the gate is already open) knows its own
/// answer is right either way.
bool isDeepForRole(
  UserRole role,
  String route, {
  bool chaptersUnlocked = true,
  FacultyMode facultyMode = FacultyMode.adviser,
}) {
  final path = Uri.parse(route).path;
  final destinations = destinationsFor(
    role: role,
    chaptersUnlocked: chaptersUnlocked,
    facultyMode: facultyMode,
  );
  return isDeeperThanDestination(destinations, path);
}
