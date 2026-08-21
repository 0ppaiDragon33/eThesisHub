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

  test('feedback is listed oldest first and carries its version', () async {
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
    await repo.addFeedback(
      thesisId: 't1', chapter: ChapterId.chapterI, version: 1,
      reviewerUid: 'a1', reviewerName: 'Dr. A', reviewerRole: 'Adviser',
      body: 'Second point.',
    );
    final feedback =
        await repo.watchFeedback('t1', ChapterId.chapterI).first;
    expect(feedback.map((f) => f.body), ['First point.', 'Second point.']);
    expect(feedback.every((f) => f.version == 1), isTrue);
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
}
