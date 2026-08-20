import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Counts how many times a stream was asked for, which is the whole point:
/// a Firestore listener is established once per subscription, and a listener
/// that was refused stays refused until a new one is opened.
class _CountingThesisRepository implements ThesisRepository {
  int watchByStatusCalls = 0;
  int watchThesisCalls = 0;

  @override
  Stream<List<Thesis>> watchByStatus(ThesisStatus status) {
    watchByStatusCalls++;
    return const Stream.empty();
  }

  @override
  Stream<Thesis?> watchThesis(String thesisId) {
    watchThesisCalls++;
    return const Stream.empty();
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  // The bug: these are plain StreamProviders, built once and kept for the
  // life of the container. A listener denied under one account stayed in
  // AsyncError forever -- signing in as somebody else did not rebuild it, so
  // a coordinator saw the previous account's refusal and only a full page
  // reload cleared it. Reported in the field as "I have to refresh for it to
  // disappear".
  group('streams whose permission depends on the user', () {
    late StreamController<User?> auth;
    late _CountingThesisRepository repo;
    late ProviderContainer container;

    setUp(() {
      auth = StreamController<User?>.broadcast();
      repo = _CountingThesisRepository();
      container = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => auth.stream),
        thesisRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      addTearDown(auth.close);
    });

    test('thesesByStatusProvider re-subscribes when the user changes',
        () async {
      final sub = container.listen(
        thesesByStatusProvider(ThesisStatus.titlePendingDefence),
        (_, _) {},
      );
      addTearDown(sub.close);

      auth.add(MockUser(uid: 'dean-1', email: 'd@isufst.edu.ph'));
      await pumpEventQueue();
      final afterFirst = repo.watchByStatusCalls;
      expect(afterFirst, greaterThan(0));

      auth.add(MockUser(uid: 'coord-1', email: 'c@isufst.edu.ph'));
      await pumpEventQueue();

      expect(repo.watchByStatusCalls, greaterThan(afterFirst),
          reason: 'a new account must open a new listener, or it inherits '
              'the previous account\'s refusal until the page is reloaded');
    });

    test('thesisByIdProvider re-subscribes when the user changes', () async {
      final sub = container.listen(thesisByIdProvider('t1'), (_, _) {});
      addTearDown(sub.close);

      auth.add(MockUser(uid: 'dean-1', email: 'd@isufst.edu.ph'));
      await pumpEventQueue();
      final afterFirst = repo.watchThesisCalls;
      expect(afterFirst, greaterThan(0));

      auth.add(MockUser(uid: 'coord-1', email: 'c@isufst.edu.ph'));
      await pumpEventQueue();

      expect(repo.watchThesisCalls, greaterThan(afterFirst));
    });

    test('a token refresh alone does not churn the listener', () async {
      // authStateChanges also fires on token refresh, which does not change
      // who is asking. Rebuilding then would drop and reopen every Firestore
      // listener in the app for nothing.
      final sub = container.listen(
        thesesByStatusProvider(ThesisStatus.titlePendingDefence),
        (_, _) {},
      );
      addTearDown(sub.close);

      final user = MockUser(uid: 'dean-1', email: 'd@isufst.edu.ph');
      auth.add(user);
      await pumpEventQueue();
      final afterFirst = repo.watchByStatusCalls;

      auth.add(MockUser(uid: 'dean-1', email: 'd@isufst.edu.ph'));
      await pumpEventQueue();

      expect(repo.watchByStatusCalls, afterFirst,
          reason: 'the same uid is the same person');
    });
  });
}
