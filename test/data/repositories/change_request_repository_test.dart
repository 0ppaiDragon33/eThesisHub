import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/repositories/change_request_repository.dart';

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'panelistUids': <String>['p1'],
    'memberNames': <String>[],
    'workingTitle': 'Old Title',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'status': 'titleApproved',
  });
  return db;
}

Future<Thesis> theThesis(FakeFirebaseFirestore db) async =>
    Thesis.fromMap('t1', (await db.doc('theses/t1').get()).data()!);

FacultyDirectoryEntry newAdv() => const FacultyDirectoryEntry(
  uid: 'a2',
  fullName: 'Dr. New',
  role: 'faculty',
);

void main() {
  test(
    'submitting an adviser change creates a pendingAdvisers request',
    () async {
      final db = await seed();
      final repo = ChangeRequestRepository(db);
      await repo.submitAdviserChange(
        thesis: await theThesis(db),
        newAdviser: newAdv(),
        formerAdviserName: 'Dr. Old',
        reasons: 'The adviser moved campus.',
      );
      final list = await repo.watchForThesis('t1').first;
      expect(list.single.type, ChangeRequestType.adviser);
      expect(list.single.stage, ChangeRequestStage.pendingAdvisers);
      expect(list.single.newAdviserUid, 'a2');
      expect(list.single.formerAdviserUid, 'a1');
      expect(list.single.signoffs['newAdviser']!.status, SignoffStatus.pending);
    },
  );

  test('a title change creates a pendingAdviser request', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
      thesis: await theThesis(db),
      newTitle: 'A Better Title',
      reasons: 'x',
    );
    final r = (await repo.watchForThesis('t1').first).single;
    expect(r.type, ChangeRequestType.title);
    expect(r.stage, ChangeRequestStage.pendingAdviser);
    expect(r.newTitle, 'A Better Title');
  });

  test(
    'the new adviser accepting holds the stage until the former does',
    () async {
      final db = await seed();
      final repo = ChangeRequestRepository(db);
      await repo.submitAdviserChange(
        thesis: await theThesis(db),
        newAdviser: newAdv(),
        formerAdviserName: 'Dr. Old',
        reasons: 'x',
      );

      await repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.adviser,
        role: 'newAdviser',
        accept: true,
      );
      var r = (await repo.watchForThesis('t1').first).single;
      expect(r.stage, ChangeRequestStage.pendingAdvisers);

      await repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.adviser,
        role: 'formerAdviser',
        accept: true,
      );
      r = (await repo.watchForThesis('t1').first).single;
      expect(r.stage, ChangeRequestStage.pendingCoordinator);
    },
  );

  test('a decline returns the request with the reason', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
      thesis: await theThesis(db),
      newTitle: 'X',
      reasons: 'y',
    );
    await repo.respond(
      thesisId: 't1',
      type: ChangeRequestType.title,
      role: 'adviser',
      accept: false,
      reason: 'Too broad.',
    );
    final r = (await repo.watchForThesis('t1').first).single;
    expect(r.stage, ChangeRequestStage.returned);
    expect(r.signoffs['adviser']!.status, SignoffStatus.declined);
    expect(r.signoffs['adviser']!.reason, 'Too broad.');
  });

  test(
    'the coordinator then Dean approval applies the adviser change',
    () async {
      final db = await seed();
      final repo = ChangeRequestRepository(db);
      await repo.submitAdviserChange(
        thesis: await theThesis(db),
        newAdviser: newAdv(),
        formerAdviserName: 'Dr. Old',
        reasons: 'x',
      );
      await repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.adviser,
        role: 'newAdviser',
        accept: true,
      );
      await repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.adviser,
        role: 'formerAdviser',
        accept: true,
      );
      await repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.adviser,
        role: 'coordinator',
        accept: true,
      );
      await repo.approveAsDean(thesisId: 't1', type: ChangeRequestType.adviser);

      expect((await theThesis(db)).adviserUid, 'a2');
      final r = (await repo.watchForThesis('t1').first).single;
      expect(r.stage, ChangeRequestStage.approved);
    },
  );

  test('the Dean approval applies the title change', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
      thesis: await theThesis(db),
      newTitle: 'A Better Title',
      reasons: 'x',
    );
    for (final role in ['adviser', 'coordinator']) {
      await repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.title,
        role: role,
        accept: true,
      );
    }
    await repo.approveAsDean(thesisId: 't1', type: ChangeRequestType.title);
    expect((await theThesis(db)).workingTitle, 'A Better Title');
  });

  test('responding at the wrong stage is refused', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
      thesis: await theThesis(db),
      newTitle: 'X',
      reasons: 'y',
    );
    // The coordinator cannot act while the adviser has not.
    await expectLater(
      repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.title,
        role: 'coordinator',
        accept: true,
      ),
      throwsStateError,
    );
  });

  test('approving applies nothing if the thesis left titleApproved', () async {
    final db = await seed();
    final repo = ChangeRequestRepository(db);
    await repo.submitTitleChange(
      thesis: await theThesis(db),
      newTitle: 'X',
      reasons: 'y',
    );
    for (final role in ['adviser', 'coordinator']) {
      await repo.respond(
        thesisId: 't1',
        type: ChangeRequestType.title,
        role: role,
        accept: true,
      );
    }
    await db.doc('theses/t1').update({'status': 'archived'});
    await expectLater(
      repo.approveAsDean(thesisId: 't1', type: ChangeRequestType.title),
      throwsStateError,
    );
  });
}
