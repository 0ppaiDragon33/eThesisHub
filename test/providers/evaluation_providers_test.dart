import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation.dart';
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

ProviderContainer containerFor(FakeFirebaseFirestore db, String uid) {
  final mockUser = MockUser(uid: uid);
  return ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(
      MockFirebaseAuth(signedIn: true, mockUser: mockUser),
    ),
    authStateProvider.overrideWith((ref) {
      return Stream.value(mockUser as User?);
    }),
  ]);
}

void main() {
  test('defenceEvaluationsProvider yields both sheets in uid order',
      () async {
    final c = containerFor(await seed(), 'p1');
    addTearDown(c.dispose);

    final list = await c.read(defenceEvaluationsProvider('d1').future);
    expect(list.map((e) => e.evaluatorUid), ['p1', 'p2']);
  });

  test('myEvaluationProvider yields only the signed-in panelist\'s',
      () async {
    final c = containerFor(await seed(), 'p2');
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
      authStateProvider.overrideWith((ref) => Stream.value(null as User?)),
    ]);
    addTearDown(c.dispose);

    expect(await c.read(myEvaluationProvider('d1').future), isNull);
  });

  test('myEvaluationProvider is null when this panelist has not submitted',
      () async {
    final c = containerFor(await seed(), 'p3');
    addTearDown(c.dispose);

    expect(await c.read(myEvaluationProvider('d1').future), isNull);
  });
}
