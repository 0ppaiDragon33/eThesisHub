import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1',
    'panelistUids': <String>['p1', 'p2', 'p3'],
    'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    'status': 'titleApproved',
  });
  return db;
}

Future<String> scheduleOne(DefenceRepository repo,
    {DefenceType type = DefenceType.preOral}) {
  return repo.schedule(
    thesisId: 't1',
    type: type,
    scheduledAt: DateTime.utc(2026, 9, 1, 9),
    venue: 'CICT AVR',
    panelUids: const ['p1', 'p2', 'p3'],
    adviserUid: 'a1',
    leaderUid: 'l1',
    createdBy: 'c1',
  );
}

void main() {
  test('a scheduled defence starts at scheduled and unreleased', () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    final id = await scheduleOne(repo);
    final d = await repo.watchDefence(id).first;

    expect(d!.status, DefenceStatus.scheduled);
    expect(d.isReleased, isFalse);
    expect(d.panelUids, ['p1', 'p2', 'p3']);
    expect(d.adviserUid, 'a1');
    expect(d.leaderUid, 'l1');
  });

  test('the lifecycle moves forward only', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    final id = await scheduleOne(repo);

    await repo.setStatus(defenceId: id, status: DefenceStatus.inProgress);
    expect((await repo.watchDefence(id).first)!.status,
        DefenceStatus.inProgress);

    // The rules deny this too, but fake_cloud_firestore enforces none, so
    // without the check here the app would report success and write a state
    // no real user could reach.
    await expectLater(
      repo.setStatus(defenceId: id, status: DefenceStatus.scheduled),
      throwsStateError,
    );
    // `returnsNormally` matches a `Function`, not a `Future` — passing the
    // pending future to expectLater always fails with a type mismatch
    // regardless of outcome, so this asserts success by awaiting directly:
    // an unhandled throw here fails the test on its own.
    await repo.setStatus(defenceId: id, status: DefenceStatus.completed);
  });

  test('skipping inProgress is refused', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    final id = await scheduleOne(repo);

    await expectLater(
      repo.setStatus(defenceId: id, status: DefenceStatus.completed),
      throwsStateError,
    );
  });

  test('a comment is refused unless the defence is in progress', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    final id = await scheduleOne(repo);

    Future<void> comment() => repo.addComment(
          defenceId: id, authorUid: 'p1', authorName: 'Dr. Panel',
          authorPosition: 'Panel Member', body: 'A remark.',
        );

    await expectLater(comment(), throwsStateError);

    await repo.setStatus(defenceId: id, status: DefenceStatus.inProgress);
    await comment();
    expect(await repo.watchComments(id).first, hasLength(1));

    await repo.setStatus(defenceId: id, status: DefenceStatus.completed);
    await expectLater(comment(), throwsStateError);
  });

  test('an empty remark is refused', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    final id = await scheduleOne(repo);
    await repo.setStatus(defenceId: id, status: DefenceStatus.inProgress);

    await expectLater(
      repo.addComment(
        defenceId: id, authorUid: 'p1', authorName: 'Dr. Panel',
        authorPosition: 'Panel Member', body: '   ',
      ),
      throwsArgumentError,
    );
  });

  test('comments come back oldest first, whatever order they arrive in',
      () async {
    // Seeded against the expected order on purpose: fake_cloud_firestore
    // returns documents in insertion order, so a test that inserts them
    // already sorted would pass with the sort deleted.
    final db = await seed();
    final repo = DefenceRepository(db);
    final id = await scheduleOne(repo);
    final comments = db.collection('defenses').doc(id).collection('comments');
    await comments.doc('b').set({
      'authorUid': 'p1', 'authorName': 'Dr. Panel',
      'authorPosition': 'Panel Member', 'body': 'Second.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 9, 20)),
    });
    await comments.doc('a').set({
      'authorUid': 'p1', 'authorName': 'Dr. Panel',
      'authorPosition': 'Panel Member', 'body': 'First.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 9, 10)),
    });

    final got = await repo.watchComments(id).first;
    expect(got.map((c) => c.body), ['First.', 'Second.']);
  });

  test('release is refused until the defence is completed', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    final id = await scheduleOne(repo);
    await repo.setStatus(defenceId: id, status: DefenceStatus.inProgress);

    await expectLater(repo.release(id), throwsStateError);

    await repo.setStatus(defenceId: id, status: DefenceStatus.completed);
    await repo.release(id);
    expect((await repo.watchDefence(id).first)!.isReleased, isTrue);

    // Releasing twice would let a re-release hide comments the group read.
    await expectLater(repo.release(id), throwsStateError);
  });

  test('each role query returns only its own defences', () async {
    final db = await seed();
    await db.collection('theses').doc('t2').set({
      'leaderUid': 'l2', 'adviserUid': 'other',
      'panelistUids': <String>['other-p'], 'memberNames': <String>[],
      'workingTitle': 'Other', 'college': 'CICT', 'program': 'BSIT',
      'semester': 'First', 'academicYear': '2026-2027',
      'status': 'titleApproved',
    });
    final repo = DefenceRepository(db);
    await scheduleOne(repo);
    await repo.schedule(
      thesisId: 't2', type: DefenceType.final_,
      scheduledAt: DateTime.utc(2026, 9, 2), venue: 'AVR',
      panelUids: const ['other-p'], adviserUid: 'other', leaderUid: 'l2',
      createdBy: 'c1',
    );

    expect(await repo.watchForAdviser('a1').first, hasLength(1));
    expect(await repo.watchForPanelist('p1').first, hasLength(1));
    expect(await repo.watchForLeader('l1').first, hasLength(1));
    expect(await repo.watchAll().first, hasLength(2));
  });
}
