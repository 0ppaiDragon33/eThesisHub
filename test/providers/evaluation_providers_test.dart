import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1', 'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR', 'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
    'createdBy': 'c1',
  });
  for (final uid in ['p2', 'p1']) {
    await db
        .collection('defenses').doc('d1')
        .collection('evaluations').doc(uid)
        .set({
      'scores': {for (final c in evaluationCriteria) c.key: c.weight},
      'comments': const <String, String>{},
      'total': 100,
      'rating': 'pass',
    });
  }
  return db;
}

// `signedInUidProvider` derives synchronously from
// `authStateProvider.valueOrNull` (see auth_providers.dart), and
// `MockFirebaseAuth`'s own first `authStateChanges()` event is delivered
// asynchronously -- so a provider read straight after container creation
// can observe `signedInUidProvider` still at its initial `null` and never
// get another chance, because `.future` is bound to that first build.
// Awaiting `authStateProvider.future` here settles that race the same way
// `currentUserProvider` does in production: once this returns, the auth
// state has genuinely emitted and `signedInUidProvider` reads the real uid.
Future<ProviderContainer> containerFor(
  FakeFirebaseFirestore db,
  String uid,
) async {
  final mockUser = MockUser(uid: uid);
  final c = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(
      MockFirebaseAuth(signedIn: true, mockUser: mockUser),
    ),
  ]);
  await c.read(authStateProvider.future);
  return c;
}

void main() {
  test('defenceEvaluationsProvider yields both sheets in uid order',
      () async {
    final c = await containerFor(await seed(), 'p1');
    addTearDown(c.dispose);

    final list = await c.read(defenceEvaluationsProvider('d1').future);
    expect(list.map((e) => e.evaluatorUid), ['p1', 'p2']);
  });

  test('myEvaluationProvider yields only the signed-in panelist\'s',
      () async {
    final c = await containerFor(await seed(), 'p2');
    addTearDown(c.dispose);

    final mine = await c.read(myEvaluationProvider('d1').future);
    expect(mine!.evaluatorUid, 'p2');
  });

  test('myEvaluationProvider is null when nobody is signed in', () async {
    final db = await seed();
    final c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider
          .overrideWithValue(MockFirebaseAuth(signedIn: false)),
    ]);
    addTearDown(c.dispose);
    await c.read(authStateProvider.future);

    expect(await c.read(myEvaluationProvider('d1').future), isNull);
  });

  test('myEvaluationProvider is null when this panelist has not submitted',
      () async {
    final c = await containerFor(await seed(), 'p3');
    addTearDown(c.dispose);

    expect(await c.read(myEvaluationProvider('d1').future), isNull);
  });
}
