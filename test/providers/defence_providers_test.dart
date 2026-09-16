import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Counts how many times `watchAll` was asked for. A Firestore listener is
/// opened once per subscription, and a `list` on `defenses` that was refused
/// (because the auth token had not attached to the SDK yet on a cold sign-in)
/// stays in AsyncError until a NEW listener is opened. Re-subscribing on a
/// user change is what opens that new, now-authenticated listener.
class _CountingDefenceRepository extends DefenceRepository {
  _CountingDefenceRepository() : super(FakeFirebaseFirestore());

  int watchAllCalls = 0;

  @override
  Stream<List<Defence>> watchAll() {
    watchAllCalls++;
    return const Stream.empty();
  }
}

void main() {
  // The field report ("Defences this week -- Could not load" and "Could not
  // work out what needs you" on a fresh coordinator/dean login, gone after a
  // manual refresh) traced to allDefencesProvider: it was the one user-scoped
  // stream that did NOT rebuild when the signed-in user resolved, so the cold
  // permission-denied stuck. Its siblings (defenceProvider,
  // defenceCommentsProvider) already watch signedInUidProvider; this pins that
  // allDefencesProvider does too.
  group('allDefencesProvider', () {
    late StreamController<User?> auth;
    late _CountingDefenceRepository repo;
    late ProviderContainer container;

    setUp(() {
      auth = StreamController<User?>.broadcast();
      repo = _CountingDefenceRepository();
      container = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => auth.stream),
        defenceRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      addTearDown(auth.close);
    });

    test('re-subscribes when the user changes', () async {
      final sub = container.listen(allDefencesProvider, (_, _) {});
      addTearDown(sub.close);

      auth.add(MockUser(uid: 'coord-1', email: 'c@isufst.edu.ph'));
      await pumpEventQueue();
      final afterFirst = repo.watchAllCalls;
      expect(afterFirst, greaterThan(0));

      auth.add(MockUser(uid: 'dean-1', email: 'd@isufst.edu.ph'));
      await pumpEventQueue();

      expect(repo.watchAllCalls, greaterThan(afterFirst),
          reason: 'a new account must open a new listener, or it inherits the '
              'cold sign-in refusal until the page is reloaded');
    });

    test('a token refresh alone does not churn the listener', () async {
      final sub = container.listen(allDefencesProvider, (_, _) {});
      addTearDown(sub.close);

      auth.add(MockUser(uid: 'coord-1', email: 'c@isufst.edu.ph'));
      await pumpEventQueue();
      final afterFirst = repo.watchAllCalls;

      // authStateChanges also fires on token refresh -- same uid, same person.
      auth.add(MockUser(uid: 'coord-1', email: 'c@isufst.edu.ph'));
      await pumpEventQueue();

      expect(repo.watchAllCalls, afterFirst,
          reason: 'the same uid is the same person');
    });
  });
}
