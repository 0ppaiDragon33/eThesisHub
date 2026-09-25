import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

Map<String, dynamic> thesis({
  String leaderUid = 'l1',
  String adviserUid = 'a1',
  String status = 'titlePendingDefence',
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': adviserUid,
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': 'A Working Title',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

Future<ProviderContainer> containerFor(
    FakeFirebaseFirestore db, String uid, String role) async {
  await db.collection('users').doc(uid).set({
    'fullName': 'Test $uid',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  final c = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// The provider is synchronous over streams, so let them emit until it
/// settles on a value.
Future<List<Thesis>> settle(ProviderContainer c) async {
  final sub = c.listen(myTitleDefencesProvider, (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 100; i++) {
    final v = c.read(myTitleDefencesProvider);
    if (v.hasValue) return v.value!;
    if (v.hasError) throw v.error!;
    await Future<void>.delayed(Duration.zero);
  }
  fail('myTitleDefencesProvider never settled');
}

void main() {
  test('the coordinator sees every thesis at title defence', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis());
    await db.collection('theses').doc('t2').set(thesis());
    await db.collection('theses').doc('t3').set(thesis(status: 'titleApproved'));
    final c = await containerFor(db, 'c1', 'coordinator');
    expect((await settle(c)).map((t) => t.id).toSet(), {'t1', 't2'});
  });

  test('an adviser sees their advisee at title defence, with no nomination',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await db.collection('theses').doc('t2')
        .set(thesis(adviserUid: 'f1', status: 'titleApproved'));
    final c = await containerFor(db, 'f1', 'faculty');
    expect((await settle(c)).map((t) => t.id), ['t1']);
  });

  test('a panelist sees a thesis they sit on', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t2').set(thesis(adviserUid: 'a9'));
    await db.doc('theses/t2/nominations/f1')
        .set({'nomineeUid': 'f1', 'conformeStatus': 'accepted'});
    final c = await containerFor(db, 'f1', 'faculty');
    expect((await settle(c)).map((t) => t.id), ['t2']);
  });

  test('advising and sitting on the same thesis lists it once', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await db.doc('theses/t1/nominations/f1')
        .set({'nomineeUid': 'f1', 'conformeStatus': 'accepted'});
    final c = await containerFor(db, 'f1', 'faculty');
    expect((await settle(c)).map((t) => t.id), ['t1']);
  });

  test('a nomination whose thesis is gone is skipped, not an error',
      () async {
    final db = FakeFirebaseFirestore();
    await db.doc('theses/gone/nominations/f1')
        .set({'nomineeUid': 'f1', 'conformeStatus': 'accepted'});
    final c = await containerFor(db, 'f1', 'faculty');
    expect(await settle(c), isEmpty);
  });

  test('a student sees their own thesis only while it is at title defence',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 's1'));
    final c = await containerFor(db, 's1', 'student');
    expect((await settle(c)).map((t) => t.id), ['t1']);

    await db.collection('theses').doc('t1')
        .update({'status': 'titleApproved'});
    await Future<void>.delayed(Duration.zero);
    expect(await settle(c), isEmpty);
  });
}
