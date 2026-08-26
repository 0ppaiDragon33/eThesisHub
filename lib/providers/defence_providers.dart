import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final defenceRepositoryProvider = Provider<DefenceRepository>(
  (ref) => DefenceRepository(ref.watch(firestoreProvider)),
);

/// Every defence in the college, unfiltered -- straight off
/// [defenceRepositoryProvider] rather than through [myDefencesProvider].
///
/// [myDefencesProvider] awaits `currentUserProvider.future` before it can
/// decide which query to run, so anything reading it inherits a dependency
/// on `users/{uid}` resolving. That dependency does not hang -- `watchUser`
/// resolves to `null` for a missing profile rather than staying pending --
/// but a `null` profile does not match the coordinator/dean branch either,
/// so a coordinator or dean without a profile document silently falls
/// through to the faculty adviser/panel fan-in and sees the wrong count
/// instead of the college-wide one. That is the exact race window an
/// earlier milestone's lockout bug came from (see the "never blocks on the
/// profile document" notes on the overview screens), so anything on an
/// overview that wants "every defence" -- a coordinator's or dean's
/// "Defences this week" tile, or [coordinatorNeedsYouProvider]'s own
/// "no defence scheduled" check -- reads it from here instead.
final allDefencesProvider = StreamProvider<List<Defence>>(
  (ref) => ref.watch(defenceRepositoryProvider).watchAll(),
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
  // A faculty member advises one group and sits on other panels, and those
  // are separate `allow list` arms -- no single query returns both. This is
  // a genuine fan-in, not a sample: an earlier shape advanced only when the
  // ADVISER stream emitted and re-read the panel side with `.first`, so a
  // defence that added this member to a panel and touched nothing else
  // never arrived at all.
  final controller = StreamController<List<Defence>>();
  List<Defence> advised = const [];
  List<Defence> panelled = const [];
  var sawAdvised = false;
  var sawPanelled = false;

  void emit() {
    // Wait for one snapshot from each before emitting, so the list never
    // renders half the schedule as if it were the whole of it.
    if (!sawAdvised || !sawPanelled) return;
    final byId = {for (final d in [...advised, ...panelled]) d.id: d};
    final merged = byId.values.toList()
      ..sort((a, b) {
        final at = a.scheduledAt;
        final bt = b.scheduledAt;
        if (at == null || bt == null) return a.id.compareTo(b.id);
        final byTime = at.compareTo(bt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    controller.add(merged);
  }

  final subs = [
    repo.watchForAdviser(uid).listen((v) {
      advised = v;
      sawAdvised = true;
      emit();
    }, onError: controller.addError),
    repo.watchForPanelist(uid).listen((v) {
      panelled = v;
      sawPanelled = true;
      emit();
    }, onError: controller.addError),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    controller.close();
  });
  yield* controller.stream;
});
