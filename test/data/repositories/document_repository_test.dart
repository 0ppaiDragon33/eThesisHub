import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/repositories/document_repository.dart';

Future<FakeFirebaseFirestore> seed({String status = 'titleApproved'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': status,
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  return db;
}

void main() {
  test('the first upload creates the chapter at version 1', () async {
    final db = await seed();
    final repo = DocumentRepository(db);

    await repo.addVersion(
      thesisId: 't1', chapter: ChapterId.chapterI,
      storagePath: 'p', fileUrl: 'u', mimeType: 'application/pdf',
      sizeBytes: 10, uploadedBy: 'l1',
    );

    final chapters = await repo.watchChapters('t1').first;
    expect(chapters.single.id, ChapterId.chapterI);
    expect(chapters.single.currentVersion, 1);
    expect(chapters.single.status, ChapterStatus.submitted);

    final versions =
        await repo.watchVersions('t1', ChapterId.chapterI).first;
    expect(versions.single.version, 1);
  });

  test('a second upload increments the version and keeps the first',
      () async {
    final db = await seed();
    final repo = DocumentRepository(db);
    for (var i = 0; i < 2; i++) {
      await repo.addVersion(
        thesisId: 't1', chapter: ChapterId.chapterI,
        storagePath: 'p$i', fileUrl: 'u$i', mimeType: 'application/pdf',
        sizeBytes: 10, uploadedBy: 'l1',
      );
    }
    final chapters = await repo.watchChapters('t1').first;
    expect(chapters.single.currentVersion, 2);

    final versions =
        await repo.watchVersions('t1', ChapterId.chapterI).first;
    expect(versions.map((v) => v.version), [2, 1]); // newest first
    expect(versions.map((v) => v.storagePath), ['p1', 'p0']);
  });

  test('uploading onto an approved chapter is refused before any write',
      () async {
    // The rules deny it too, but fake_cloud_firestore does not enforce
    // rules -- without this check the app would report success and write
    // nothing anyone could see.
    final db = await seed();
    final repo = DocumentRepository(db);
    await repo.addVersion(
      thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p',
      fileUrl: 'u', mimeType: 'application/pdf', sizeBytes: 10,
      uploadedBy: 'l1',
    );
    await repo.setChapterStatus(
      thesisId: 't1', chapter: ChapterId.chapterI,
      status: ChapterStatus.approved,
    );

    await expectLater(
      repo.addVersion(
        thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p2',
        fileUrl: 'u2', mimeType: 'application/pdf', sizeBytes: 10,
        uploadedBy: 'l1',
      ),
      throwsStateError,
    );
    final versions =
        await repo.watchVersions('t1', ChapterId.chapterI).first;
    expect(versions.length, 1, reason: 'nothing was written');
  });

  test('uploading before the title is approved is refused', () async {
    final db = await seed(status: 'titlePendingDefence');
    final repo = DocumentRepository(db);
    await expectLater(
      repo.addVersion(
        thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p',
        fileUrl: 'u', mimeType: 'application/pdf', sizeBytes: 10,
        uploadedBy: 'l1',
      ),
      throwsStateError,
    );
  });

  test('chapters come back in I-V order regardless of upload order',
      () async {
    // Seeded deliberately out of reading order. Lexically the ids DO sort
    // correctly (chapterI < chapterII < chapterIII < chapterIV < chapterV),
    // so a lexical-id test would pass by accident; what actually needs
    // proving is that watchChapters sorts explicitly rather than trusting
    // Firestore's document order, which fake_cloud_firestore returns as
    // insertion order -- V, II, IV in the order they were written below.
    final db = await seed();
    // IV and V need a passed pre-oral to be uploaded at all.
    await db.collection('defenses').doc('po').set({
      'thesisId': 't1', 'type': 'preOral', 'leaderUid': 'l1',
      'status': 'completed', 'panelVerdict': 'pass',
    });
    final repo = DocumentRepository(db);
    for (final c in [ChapterId.chapterV, ChapterId.chapterII,
                     ChapterId.chapterIV]) {
      await repo.addVersion(
        thesisId: 't1', chapter: c, storagePath: 'p', fileUrl: 'u',
        mimeType: 'application/pdf', sizeBytes: 10, uploadedBy: 'l1',
      );
    }
    final chapters = await repo.watchChapters('t1').first;
    expect(chapters.map((c) => c.id),
        [ChapterId.chapterII, ChapterId.chapterIV, ChapterId.chapterV]);
  });

  test('feedback is listed oldest first, whatever order it arrives in',
      () async {
    // Seeded newest-first on purpose: fake_cloud_firestore returns documents
    // in insertion order, so a test that inserts them already-sorted would
    // pass with the sort deleted.
    final db = await seed();
    final feedback = db.collection('theses').doc('t1')
        .collection('documents').doc('chapterI').collection('feedback');
    await feedback.doc('b').set({
      'version': 1, 'reviewerUid': 'a1', 'reviewerName': 'Dr. A',
      'reviewerRole': 'Adviser', 'body': 'Second point.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 21, 10, 5)),
    });
    await feedback.doc('a').set({
      'version': 1, 'reviewerUid': 'a1', 'reviewerName': 'Dr. A',
      'reviewerRole': 'Adviser', 'body': 'First point.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 21, 10, 0)),
    });

    final items = await DocumentRepository(db)
        .watchFeedback('t1', ChapterId.chapterI).first;
    expect(items.map((f) => f.body), ['First point.', 'Second point.']);
  });

  test('addFeedback writes the fields it was given', () async {
    final db = await seed();
    final repo = DocumentRepository(db);
    await repo.addVersion(
      thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p',
      fileUrl: 'u', mimeType: 'application/pdf', sizeBytes: 10,
      uploadedBy: 'l1',
    );
    await repo.addFeedback(
      thesisId: 't1', chapter: ChapterId.chapterI, version: 1,
      reviewerUid: 'a1', reviewerName: 'Dr. A', reviewerRole: 'Adviser',
      body: 'First point.',
    );
    final feedback =
        await repo.watchFeedback('t1', ChapterId.chapterI).first;
    expect(feedback.single.version, 1);
    expect(feedback.single.reviewerUid, 'a1');
    expect(feedback.single.reviewerName, 'Dr. A');
    expect(feedback.single.reviewerRole, 'Adviser');
    expect(feedback.single.body, 'First point.');
  });

  test('empty feedback is refused', () async {
    final db = await seed();
    final repo = DocumentRepository(db);
    await expectLater(
      repo.addFeedback(
        thesisId: 't1', chapter: ChapterId.chapterI, version: 1,
        reviewerUid: 'a1', reviewerName: 'Dr. A', reviewerRole: 'Adviser',
        body: '   ',
      ),
      throwsArgumentError,
    );
  });

  group('Chapters IV and V wait for a passed pre-oral', () {
    Future<void> defence(FakeFirebaseFirestore db, String id,
            {String type = 'preOral',
            String? verdict,
            String thesisId = 't1'}) =>
        db.collection('defenses').doc(id).set({
          'thesisId': thesisId,
          'type': type,
          'leaderUid': 'l1',
          'adviserUid': 'a1',
          'panelUids': <String>['p1'],
          'status': 'completed',
          'panelVerdict': ?verdict,
        });

    Future<void> upload(DocumentRepository repo, ChapterId chapter) =>
        repo.addVersion(
          thesisId: 't1', chapter: chapter,
          storagePath: 'p', fileUrl: 'u', mimeType: 'application/pdf',
          sizeBytes: 10, uploadedBy: 'l1',
        );

    test('refused while the pre-oral has not passed', () async {
      final db = await seed();
      // A failed pre-oral, one with no verdict yet, a passed final (not a
      // pre-oral) and another thesis's passed pre-oral all count for nothing.
      await defence(db, 'po-fail', verdict: 'fail');
      await defence(db, 'po-open');
      await defence(db, 'fin', type: 'final', verdict: 'pass');
      await defence(db, 'other', verdict: 'pass', thesisId: 't2');
      final repo = DocumentRepository(db);

      for (final c in [ChapterId.chapterIV, ChapterId.chapterV]) {
        await expectLater(upload(repo, c), throwsStateError, reason: c.name);
      }
      expect((await db.collection('theses/t1/documents').get()).docs, isEmpty);
      // Chapters I-III are untouched by the rule.
      await upload(repo, ChapterId.chapterIII);
    });

    test('allowed once it passed, naming the defence it relies on',
        () async {
      final db = await seed();
      await defence(db, 'po-fail', verdict: 'fail');
      // The re-defence that passed is a pre-oral too.
      await defence(db, 'po-fail_redefence', verdict: 'pass');
      final repo = DocumentRepository(db);

      await upload(repo, ChapterId.chapterIV);
      final doc = await db.doc('theses/t1/documents/chapterIV').get();
      expect(doc.data()!['preOralDefenceId'], 'po-fail_redefence');

      // The next version keeps naming it.
      await upload(repo, ChapterId.chapterIV);
      final again = await db.doc('theses/t1/documents/chapterIV').get();
      expect(again.data()!['currentVersion'], 2);
      expect(again.data()!['preOralDefenceId'], 'po-fail_redefence');
    });
  });
}
