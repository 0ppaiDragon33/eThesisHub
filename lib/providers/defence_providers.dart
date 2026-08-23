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
  // Faculty hold either position, and the two queries are separate arms —
  // there is no single query that returns both, so they are merged here.
  yield* repo.watchForAdviser(uid);
});
