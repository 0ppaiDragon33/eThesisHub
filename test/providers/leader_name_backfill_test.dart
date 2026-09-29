import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// A leader `l1` named Karlo June Bagsain, with a thesis created before
/// `leaderName` existed (so it carries none), unless [leaderName] is given.
Future<FakeFirebaseFirestore> seed({String? leaderName}) async {
  final db = FakeFirebaseFirestore();
  await db.doc('users/l1').set({
    'fullName': 'Karlo June Bagsain',
    'email': 'l1@isufst.edu.ph',
    'role': 'student',
    'active': true,
  });
  await db.doc('theses/t1').set({
    'leaderUid': 'l1',
    'workingTitle': 'Teachers Instructional practices',
    'memberNames': <String>[],
    'status': 'titleApproved',
    'panelistUids': <String>[],
    'leaderName': ?leaderName,
  });
  return db;
}

Future<void> run(FakeFirebaseFirestore db, String uid) async {
  final c = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
  addTearDown(c.dispose);
  final sub = c.listen(leaderNameBackfillProvider, (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 50; i++) {
    await pumpEventQueue();
  }
}

void main() {
  test("fills in the leader's own name on a thesis that has none", () async {
    final db = await seed();
    await run(db, 'l1');
    expect((await db.doc('theses/t1').get()).data()!['leaderName'],
        'Karlo June Bagsain');
  });

  test('refreshes a name that is out of date', () async {
    final db = await seed(leaderName: 'Karlo Bagsain');
    await run(db, 'l1');
    expect((await db.doc('theses/t1').get()).data()!['leaderName'],
        'Karlo June Bagsain');
  });

  test('leaves the thesis alone when the name is already right', () async {
    final db = await seed(leaderName: 'Karlo June Bagsain');
    final before = (await db.doc('theses/t1').get()).data();
    await run(db, 'l1');
    expect((await db.doc('theses/t1').get()).data(), before);
  });
}
