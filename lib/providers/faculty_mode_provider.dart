import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The mode actually in force, which is the stored preference clamped to the
/// positions the member really holds.
///
/// The stored value is a preference, not an authority. Without the clamp a
/// newly invited panelist is stranded: `FacultyMode.fromString(null)` returns
/// `adviser`, so they land on an empty Advisees list — and they cannot leave,
/// because the switch is hidden precisely when they hold no adviser position.
///
/// Holding neither position resolves to panelist. Both lists are empty either
/// way, but Nominations sits beside Panels, and the Conforme request that
/// prompted the invite is the one thing actually waiting for them.
///
/// Async on purpose. Collapsing the unresolved state into a default would
/// flip the mode visibly on every launch, and would tell an adviser-only
/// member they are a panelist for as long as the query takes.
final effectiveFacultyModeProvider = FutureProvider<FacultyMode>((ref) async {
  final stored = ref.watch(facultyModeProvider);
  final adviserCount = await ref.watch(adviserPositionCountProvider.future);
  final panelCount = await ref.watch(panelPositionCountProvider.future);

  if (adviserCount > 0 && panelCount > 0) return stored;
  if (adviserCount > 0) return FacultyMode.adviser;
  return FacultyMode.panelist;
});

/// Work waiting in whichever mode is NOT in force, for the switch's badge.
///
/// In adviser mode it counts theses whose candidate titles are with the
/// panel; in panelist mode it counts chapters a group has submitted and the
/// adviser has not yet answered. The point of the badge is that a member
/// deep in one role can see the other filling up without switching to check.
final pendingInOtherModeProvider = FutureProvider<int>((ref) async {
  final mode = await ref.watch(effectiveFacultyModeProvider.future);

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
