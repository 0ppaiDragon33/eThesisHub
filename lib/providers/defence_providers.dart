import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final defenceRepositoryProvider = Provider<DefenceRepository>(
  (ref) => DefenceRepository(ref.watch(firestoreProvider)),
);

final defenceProvider =
    StreamProvider.family<Defence?, String>((ref, defenceId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(defenceRepositoryProvider).watchDefence(defenceId);
});

final defenceCommentsProvider =
    StreamProvider.family<List<DefenceComment>, String>((ref, defenceId) {
  ref.watch(signedInUidProvider);
  return ref.watch(defenceRepositoryProvider).watchComments(defenceId);
});

/// The defences the signed-in user belongs to.
///
/// Each role reaches them by a different query, because `allow list` on
/// `defenses` has one arm per role — a coordinator's unfiltered list would
/// be denied outright for an adviser.
final myDefencesProvider = StreamProvider<List<Defence>>((ref) async* {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) {
    yield const [];
    return;
  }
  final me = await ref.watch(currentUserProvider.future);
  final repo = ref.watch(defenceRepositoryProvider);

  if (me?.role == UserRole.coordinator || me?.role == UserRole.dean) {
    yield* repo.watchAll();
    return;
  }
  if (me?.role == UserRole.student) {
    // Filters on leaderUid, not the leader's thesis id: probed against the
    // emulator, a list query must filter on the field the matching rule arm
    // reads, and leaderUid is a snapshot on the defence itself, so no lookup
    // of the thesis is needed at all.
    yield* repo.watchForLeader(uid);
    return;
  }
  // A faculty member advises one group and sits on other panels, and the
  // two are separate `allow list` arms — there is no single query that
  // returns both, so they are merged here. Without the merge an adviser who
  // also sits on panels silently loses half their schedule.
  await for (final mine in repo.watchForAdviser(uid)) {
    final panels = await repo.watchForPanelist(uid).first;
    final byId = {for (final d in [...mine, ...panels]) d.id: d};
    final merged = byId.values.toList()
      ..sort((a, b) {
        final at = a.scheduledAt;
        final bt = b.scheduledAt;
        if (at == null || bt == null) return a.id.compareTo(b.id);
        final byTime = at.compareTo(bt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    yield merged;
  }
});
