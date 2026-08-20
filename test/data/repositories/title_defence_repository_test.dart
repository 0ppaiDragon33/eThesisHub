import 'package:cloud_firestore/cloud_firestore.dart';
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

test('a resubmission clears the previous round\'s decision', () async {
    // The whole reason the leader is locked out of the panel's remarks is
    // `titleDecidedAt` being null while a defence is under way. Leaving the
    // previous round's decision on the document kept `titleDecided()` true in
    // firestore.rules for the rest of the thesis's life, and from round 2
    // onward the student read every comment live, mid-defence. The rules now
    // REQUIRE these three to arrive null on this transition, so a client that
    // forgets the deletes is denied outright.
    final db = await seed(status: 'titleRejected', titleRound: 1);
    await db.collection('theses').doc('t1').update({
      'titleDecidedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1)),
      'titleDecidedBy': 'dean-uid',
      'titleRejectionRemark': 'Too broad.',
    });
    final repo = TitleDefenceRepository(db);

    await repo.submitCandidateTitles(
      thesisId: 't1', titles: drafts(3),
      presentationPath: 'p2', presentationUrl: 'u2',
    );

    final thesis = (await db.collection('theses').doc('t1').get()).data()!;
    expect(thesis['titleDecidedAt'], isNull);
    expect(thesis['titleDecidedBy'], isNull);
    expect(thesis['titleRejectionRemark'], isNull);
    // ...and the thesis really is back at a live defence, so those nulls are
    // exactly what shuts the student out again.
    expect(thesis['status'], ThesisStatus.titlePendingDefence.value);
    expect(thesis['titleRound'], 2);
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

  test('submitting records the order the group typed the titles in', () async {
    final db = await seed();
    final repo = TitleDefenceRepository(db);

    await repo.submitCandidateTitles(
      thesisId: 't1',
      titles: drafts(5),
      presentationPath: 'theses/t1/pres/uuid.pptx',
      presentationUrl: 'https://example.test/pres.pptx',
    );

    final docs = await db.collection('theses').doc('t1')
        .collection('candidateTitles').get();
    final byText = {
      for (final d in docs.docs)
        d.data()['titleText'] as String: d.data()['position'] as int,
    };
    expect(byText, {
      'Candidate 0': 0, 'Candidate 1': 1, 'Candidate 2': 2,
      'Candidate 3': 3, 'Candidate 4': 4,
    });
  });

  test('candidates are listed by position, not by document id', () async {
    // Seeded deliberately AGAINST the id order, because that is the bug: the
    // read had no ordering at all, so Firestore returned them by document
    // id, which is auto-generated and random -- the panel was shown the
    // group's titles shuffled, and the first one typed appeared third.
    // orderBy('submittedAt') would not have helped either: one batch writes
    // all of them, so the timestamps are identical and ties fall straight
    // back to that same random id.
    final db = await seed();
    final candidates =
        db.collection('theses').doc('t1').collection('candidateTitles');
    await candidates.doc('aaa').set({
      'titleText': 'Typed third', 'justificationPath': 'p',
      'justificationUrl': 'u', 'round': 1, 'position': 2,
    });
    await candidates.doc('bbb').set({
      'titleText': 'Typed first', 'justificationPath': 'p',
      'justificationUrl': 'u', 'round': 1, 'position': 0,
    });
    await candidates.doc('ccc').set({
      'titleText': 'Typed second', 'justificationPath': 'p',
      'justificationUrl': 'u', 'round': 1, 'position': 1,
    });

    final titles =
        await TitleDefenceRepository(db).watchCandidateTitles('t1').first;
    expect(titles.map((c) => c.titleText),
        ['Typed first', 'Typed second', 'Typed third']);
  });

  test('a resubmission is listed after the round it replaced', () async {
    // Rejected sets are kept, not deleted, so both rounds are in the same
    // collection. Round order comes first, and position orders within it.
    final db = await seed();
    final repo = TitleDefenceRepository(db);

    await repo.submitCandidateTitles(
      thesisId: 't1',
      titles: drafts(3),
      presentationPath: 'p',
      presentationUrl: 'u',
    );
    await db.collection('theses').doc('t1').update({
      'status': ThesisStatus.titleRejected.value,
    });
    await repo.submitCandidateTitles(
      thesisId: 't1',
      titles: drafts(3),
      presentationPath: 'p',
      presentationUrl: 'u',
    );

    final titles = await repo.watchCandidateTitles('t1').first;
    expect(titles.map((c) => c.round), [1, 1, 1, 2, 2, 2]);
    expect(titles.map((c) => c.position), [0, 1, 2, 0, 1, 2]);
  });
}
