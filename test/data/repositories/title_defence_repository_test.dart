import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

Future<FakeFirebaseFirestore> seed({
  String status = 'nominationApproved',
  int titleRound = 0,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'status': status, 'panelistUids': <String>[],
    'adviserUid': 'a1', 'memberNames': <String>[], 'workingTitle': 'T',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027', 'titleRound': titleRound,
  });
  return db;
}

List<CandidateTitleDraft> drafts(int n) => [
      for (var i = 0; i < n; i++)
        (
          titleText: 'Candidate $i',
          justificationPath: 'theses/t1/c$i/uuid.pdf',
          justificationUrl: 'https://example.test/c$i.pdf',
        ),
    ];

void main() {
  test('submitting writes the candidates and advances the thesis', () async {
    final db = await seed();
    final repo = TitleDefenceRepository(db);

    await repo.submitCandidateTitles(
      thesisId: 't1',
      titles: drafts(3),
      presentationPath: 'theses/t1/pres/uuid.pptx',
      presentationUrl: 'https://example.test/pres.pptx',
    );

    final titles = await repo.watchCandidateTitles('t1').first;
    expect(titles, hasLength(3));
    expect(titles.every((t) => t.round == 1), isTrue,
        reason: 'the first submission is round 1');

    final thesis = (await db.collection('theses').doc('t1').get()).data()!;
    expect(thesis['status'], ThesisStatus.titlePendingDefence.value);
    expect(thesis['titleRound'], 1);
    expect(thesis['presentationUrl'], contains('pres.pptx'));
    expect(thesis['titlesSubmittedAt'], isNotNull);
  });

  test('a resubmission increments the round and keeps the rejected set',
      () async {
    // The rejected candidates are history, not rubbish. The student sees what
    // was turned down; the panel sees whether anything actually changed.
    final db = await seed(status: 'titleRejected', titleRound: 1);
    await db.collection('theses/t1/candidateTitles').doc('old').set({
      'titleText': 'Rejected one', 'justificationPath': 'p',
      'justificationUrl': 'u', 'round': 1,
    });
    final repo = TitleDefenceRepository(db);

    await repo.submitCandidateTitles(
      thesisId: 't1', titles: drafts(3),
      presentationPath: 'p2', presentationUrl: 'u2',
    );

    final all = await repo.watchCandidateTitles('t1').first;
    expect(all, hasLength(4), reason: 'the rejected candidate is still there');
    expect(all.where((t) => t.round == 2), hasLength(3));
    expect(all.where((t) => t.round == 1), hasLength(1));
  });

  test('fewer than three candidates is refused', () async {
    final repo = TitleDefenceRepository(await seed());
    expect(
      () => repo.submitCandidateTitles(
        thesisId: 't1', titles: drafts(2),
        presentationPath: 'p', presentationUrl: 'u',
      ),
      throwsArgumentError,
    );
  });

  test('more than ten candidates is refused', () async {
    // Each candidate costs one get() in the rules. M1a measured the ceiling:
    // 19 documents in a batch commit, 20 are denied, and the Cloud limit is
    // stricter than the emulator's.
    final repo = TitleDefenceRepository(await seed());
    expect(
      () => repo.submitCandidateTitles(
        thesisId: 't1', titles: drafts(11),
        presentationPath: 'p', presentationUrl: 'u',
      ),
      throwsArgumentError,
    );
  });

  test('submitting from the wrong status is refused', () async {
    // Guarding here as well as in the rules: the repository is the layer that
    // holds the line when a screen forgets.
    final repo = TitleDefenceRepository(await seed(status: 'draft'));
    expect(
      () => repo.submitCandidateTitles(
        thesisId: 't1', titles: drafts(3),
        presentationPath: 'p', presentationUrl: 'u',
      ),
      throwsStateError,
    );
  });
}
