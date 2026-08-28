import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

const facultyModeKey = 'faculty_mode';

class FacultyModeNotifier extends Notifier<FacultyMode> {
  @override
  FacultyMode build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return FacultyMode.fromString(prefs.getString(facultyModeKey));
  }

  void set(FacultyMode mode) {
    state = mode;
    ref.read(sharedPrefsProvider).setString(facultyModeKey, mode.value);
  }
}

final facultyModeProvider =
    NotifierProvider<FacultyModeNotifier, FacultyMode>(FacultyModeNotifier.new);

/// Theses where the signed-in faculty member is the adviser.
///
/// This shipped as `Provider<int>((ref) => 0)` with a comment promising that
/// M1 would replace it. M1a and M1b came and went and it stayed zero, so the
/// dashboard's `if (holdsAdviserPositions)` was false for every user and the
/// Adviser/Panelist switch never rendered once. No test overrode it either,
/// so nothing caught it. `myAdviseesProvider` is the query that comment
/// asked for; M2 built it.
final adviserPositionCountProvider = FutureProvider<int>((ref) async {
  // Settle auth first. `myAdviseesProvider` yields an empty list — data, not
  // loading — while the uid is unresolved, because `signedInUidProvider`
  // cannot tell "still loading" from "signed out". Reading it before auth
  // lands therefore reports zero advisees, which would clamp an adviser into
  // panelist mode for as long as the query takes.
  await ref.watch(authStateProvider.future);
  final advisees = await ref.watch(myAdviseesProvider.future);
  return advisees.length;
});

/// Theses where they hold a panel seat rather than the adviser's chair.
///
/// Derived by subtracting the advised theses from every thesis they hold any
/// position on, because a direct `where('panelistUids', arrayContains: uid)`
/// is denied: `allow list` on `theses` has arms for the leader, the adviser,
/// the coordinator and the dean, and none for a panelist. The nomination
/// collection-group query is permitted and already indexed, and it returns a
/// row for the adviser too — hence the subtraction.
final panelPositionCountProvider = FutureProvider<int>((ref) async {
  await ref.watch(authStateProvider.future);
  final all = await ref.watch(myThesisIdsProvider.future);
  final advisees = await ref.watch(myAdviseesProvider.future);
  final advised = advisees.map((t) => t.id).toSet();
  return all.where((id) => !advised.contains(id)).length;
});

/// Shared by [effectiveFacultyModeProvider] and
/// [facultyHoldsBothCapabilitiesProvider], which both need the same
/// derivation and would otherwise have to keep two copies of it in sync.
/// Cheap to call twice: everything it awaits is itself a cached provider, so
/// the underlying Firestore reads happen once regardless of how many callers
/// watch this.
///
/// Capability is the union of designation and positions actually held —
/// neither subtracts. Designation adds what a member MAY become; a position
/// they already hold always grants access, because a coordinator narrowing
/// someone's designation must never make a live, approved responsibility
/// vanish from that member's own screen (spec D30). This project has
/// shipped that failure twice already: once permanently hiding a group
/// leader's upload button, once routing a profile-less dean down the
/// faculty code path.
///
/// On a failed (or missing) profile read, degrades to the position-only
/// derivation this provider used before designation existed: both positions
/// held keeps the stored preference, only one clamps to that one, and
/// holding neither resolves to panelist (Nominations sits beside Panels,
/// and the Conforme request that prompted an invite is the one thing
/// actually waiting there). `currentUserProvider` cannot tell "the read
/// failed" apart from "there is no profile document yet", and both cases
/// get the same, always-non-null answer: nothing may depend on
/// `users/{uid}` existing in order to render a mode at all.
Future<({FacultyMode? mode, bool bothCapable})> _deriveFacultyMode(
  Ref ref,
) async {
  final stored = ref.watch(facultyModeProvider);
  final adviserCount = await ref.watch(adviserPositionCountProvider.future);
  final panelCount = await ref.watch(panelPositionCountProvider.future);

  AppUser? profile;
  try {
    profile = await ref.watch(currentUserProvider.future);
  } catch (_) {
    profile = null;
  }

  if (profile == null) {
    if (adviserCount > 0 && panelCount > 0) {
      return (mode: stored, bothCapable: true);
    }
    if (adviserCount > 0) {
      return (mode: FacultyMode.adviser, bothCapable: false);
    }
    return (mode: FacultyMode.panelist, bothCapable: false);
  }

  final canAdvise = profile.nominableAsAdviser || adviserCount > 0;
  final canPanel = profile.nominableAsPanelist || panelCount > 0;

  if (canAdvise && canPanel) return (mode: stored, bothCapable: true);
  if (canAdvise) return (mode: FacultyMode.adviser, bothCapable: false);
  if (canPanel) return (mode: FacultyMode.panelist, bothCapable: false);
  return (mode: null, bothCapable: false);
}

/// The mode actually in force, or `null` when the member may reach neither
/// Advisees nor Panels.
///
/// `null` is a real, durable answer here — not a stand-in for "still
/// loading". A [FacultyMode] enum value cannot express "neither": it is
/// persisted by [facultyModeProvider], whose `fromString` defaults a
/// missing/unparseable stored value to adviser, so a third enum member would
/// be an unreachable state hiding in a stored preference and would change
/// how every already-stored value parses. The stored preference answers
/// "which do you prefer when you hold both" (always one of two); this
/// answers "which can you reach" (can genuinely be neither). Different
/// questions get different types.
///
/// Every consumer must handle `null` — that is the point. `null` is exactly
/// what suppresses the Advisees/Panels destination in `destinationsFor`
/// (spec §6): a destination leading to an empty screen reads as a broken
/// app, so "neither" declares no destination at all.
///
/// Async on purpose. Collapsing the unresolved state into a default would
/// flip the mode visibly on every launch, and would tell an adviser-only
/// member they are a panelist for as long as the query takes.
final effectiveFacultyModeProvider = FutureProvider<FacultyMode?>((ref) async {
  return (await _deriveFacultyMode(ref)).mode;
});

/// Whether the member currently holds BOTH capabilities — the gate for
/// showing the Adviser/Panelist switch at all. A member with only one
/// capability has nowhere the switch could move them, and one that could
/// only ever lead to an empty list is a control that does nothing.
///
/// Kept separate from [effectiveFacultyModeProvider] because the mode alone
/// cannot be inspected to recover this: an adviser-only member and a
/// both-capable member whose stored preference happens to be adviser both
/// resolve to `FacultyMode.adviser`.
final facultyHoldsBothCapabilitiesProvider = FutureProvider<bool>((ref) async {
  return (await _deriveFacultyMode(ref)).bothCapable;
});

/// Work waiting in whichever mode is NOT in force, for the switch's badge.
///
/// In adviser mode it counts theses whose candidate titles are with the
/// panel; in panelist mode it counts chapters a group has submitted and the
/// adviser has not yet answered. The point of the badge is that a member
/// deep in one role can see the other filling up without switching to check.
final pendingInOtherModeProvider = FutureProvider<int>((ref) async {
  final mode = await ref.watch(effectiveFacultyModeProvider.future);

  // Neither mode is reachable, so there is no "other mode" to have work
  // waiting in, and no switch for a badge to sit on.
  if (mode == null) return 0;

  if (mode == FacultyMode.adviser) {
    final ids = await ref.watch(myThesisIdsProvider.future);
    final advisees = await ref.watch(myAdviseesProvider.future);
    final advised = advisees.map((t) => t.id).toSet();
    var waiting = 0;
    for (final id in ids.where((id) => !advised.contains(id))) {
      final thesis = await ref.watch(thesisByIdProvider(id).future);
      if (thesis?.status == ThesisStatus.titlePendingDefence) waiting++;
    }
    return waiting;
  }

  final advisees = await ref.watch(myAdviseesProvider.future);
  var waiting = 0;
  for (final thesis in advisees) {
    final chapters = await ref.watch(chaptersProvider(thesis.id).future);
    waiting += chapters
        .where((c) => c.status == ChapterStatus.submitted)
        .length;
  }
  return waiting;
});
