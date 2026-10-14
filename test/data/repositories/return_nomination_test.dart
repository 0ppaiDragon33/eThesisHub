import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/repositories/thesis_repository.dart';

/// The Coordinator or the Dean sending a nomination back to the group.
Future<FakeFirebaseFirestore> seed(String status) async {
  final db = FakeFirebaseFirestore();
  await db.doc('theses/t1').set({
    'leaderUid': 'l1',
    'status': status,
    'panelistUids': <String>[],
    'adviserUid': null,
    'memberNames': <String>[],
    'workingTitle': 'T',
    'college': 'CICI',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'createdAt': Timestamp.now(),
    if (status == 'nominationPendingDean') ...{
      'coordinatorRecommendedAt': Timestamp.now(),
      'coordinatorRecommendedBy': 'c1',
    },
  });
  for (final uid in ['a1', 'p1', 'p2', 'p3']) {
    await db.doc('theses/t1/nominations/$uid').set({
      'nomineeUid': uid,
      'nomineeName': uid,
      'position': uid == 'a1' ? 'adviser' : 'panelist',
      'exOfficio': false,
      'conformeStatus': 'accepted',
      'respondedAt': null,
      'declineReason': null,
    });
  }
  return db;
}

void main() {
  test('the Coordinator returns it: draft, reason, every seat cleared',
      () async {
    final db = await seed('nominationPendingCoordinator');
    await ThesisRepository(db).returnNomination(
      thesisId: 't1',
      actorUid: 'c1',
      asDean: false,
      reason: 'Choose a panel member from CICI.',
    );

    final t = (await db.doc('theses/t1').get()).data()!;
    expect(t['status'], 'draft');
    expect(t['nominationReturnedBy'], 'c1');
    expect(t['nominationReturnedRole'], 'coordinator');
    expect(t['nominationReturnReason'], 'Choose a panel member from CICI.');
    expect(t['nominationReturnedAt'], isNotNull);
    expect((await db.collection('theses/t1/nominations').get()).docs, isEmpty);
  });

  test('the Dean returns it and the recommendation is cleared', () async {
    final db = await seed('nominationPendingDean');
    await ThesisRepository(db).returnNomination(
      thesisId: 't1',
      actorUid: 'd1',
      asDean: true,
      reason: 'The adviser is on leave.',
    );

    final t = (await db.doc('theses/t1').get()).data()!;
    expect(t['status'], 'draft');
    expect(t['nominationReturnedRole'], 'dean');
    expect(t['coordinatorRecommendedAt'], isNull);
    expect(t['coordinatorRecommendedBy'], isNull);
  });

  test('the returned thesis reads as returned', () async {
    final db = await seed('nominationPendingCoordinator');
    final repo = ThesisRepository(db);
    await repo.returnNomination(
      thesisId: 't1', actorUid: 'c1', asDean: false, reason: 'Fix it.');
    final thesis = await repo.fetchThesis('t1');
    expect(thesis!.nominationReturned, isTrue);
    expect(thesis.nominationReturnedAt, isNotNull);
  });

  test('only at your own step', () async {
    final db = await seed('nominationPendingDean');
    await expectLater(
      ThesisRepository(db).returnNomination(
          thesisId: 't1', actorUid: 'c1', asDean: false, reason: 'x'),
      throwsStateError,
    );
    expect((await db.collection('theses/t1/nominations').get()).docs,
        hasLength(4), reason: 'nothing was cleared');
  });

  test('a reason is required', () async {
    final db = await seed('nominationPendingCoordinator');
    await expectLater(
      ThesisRepository(db).returnNomination(
          thesisId: 't1', actorUid: 'c1', asDean: false, reason: '  '),
      throwsArgumentError,
    );
  });
}
