import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

Future<void> seedThesis(
  FakeFirebaseFirestore db,
  String id, {
  String status = 'nominationPendingConforme',
}) {
  return db.collection('theses').doc(id).set({
    'leaderUid': 'l1',
    'status': status,
    'panelistUids': <String>[],
    'adviserUid': null,
    'memberNames': <String>[],
    'workingTitle': 'Thesis $id',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
  });
}

Future<void> seedNomination(
  FakeFirebaseFirestore db,
  String thesisId,
  String uid,
  String conformeStatus,
) {
  return db
      .collection('theses')
      .doc(thesisId)
      .collection('nominations')
      .doc(uid)
      .set({
    'nomineeUid': uid,
    'nomineeName': 'Dr. $uid',
    'position': 'panelist',
    'exOfficio': false,
    'conformeStatus': conformeStatus,
  });
}

ProviderContainer containerWith(FakeFirebaseFirestore db) {
  final container = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'coord-1')),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a thesis whose nominee declined is listed as stalled', () async {
    final db = FakeFirebaseFirestore();
    await seedThesis(db, 'stuck');
    await seedNomination(db, 'stuck', 'p1', 'declined');
    await seedNomination(db, 'stuck', 'p2', 'accepted');

    final stalled =
        await containerWith(db).read(stalledThesesProvider.future);

    expect(stalled.map((t) => t.id), ['stuck']);
  });

  // The distinction the whole provider exists for. Most theses awaiting
  // Conforme are perfectly healthy -- nobody has answered yet -- and
  // surfacing those as work the coordinator must do would bury the few that
  // are genuinely stuck.
  test('a thesis merely awaiting answers is NOT listed', () async {
    final db = FakeFirebaseFirestore();
    await seedThesis(db, 'healthy');
    await seedNomination(db, 'healthy', 'p1', 'pending');
    await seedNomination(db, 'healthy', 'p2', 'accepted');

    final stalled =
        await containerWith(db).read(stalledThesesProvider.future);

    expect(stalled, isEmpty);
  });

  test('only the stalled one is returned when both exist', () async {
    final db = FakeFirebaseFirestore();
    await seedThesis(db, 'stuck');
    await seedNomination(db, 'stuck', 'p1', 'declined');
    await seedThesis(db, 'healthy');
    await seedNomination(db, 'healthy', 'p1', 'pending');

    final stalled =
        await containerWith(db).read(stalledThesesProvider.future);

    expect(stalled.map((t) => t.id), ['stuck']);
  });

  // A thesis at another status is not a candidate at all, however its
  // nominations read -- a declined nomination on an already-approved thesis
  // is history, not a stall.
  test('a declined nomination at another status is not stalled', () async {
    final db = FakeFirebaseFirestore();
    await seedThesis(db, 'moved-on', status: 'nominationApproved');
    await seedNomination(db, 'moved-on', 'p1', 'declined');

    final stalled =
        await containerWith(db).read(stalledThesesProvider.future);

    expect(stalled, isEmpty);
  });
}
