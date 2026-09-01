import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

Future<FakeFirebaseFirestore> seed({String status = 'titleApproved'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'panelistUids': <String>['p1', 'p2'],
    'memberNames': <String>['Santos, J.'],
    'workingTitle': 'T',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'status': status,
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
  });
  return db;
}

void main() {
  test('the leader attaches a manuscript and it reads back', () async {
    final db = await seed();
    final repo = ThesisRepository(db);

    await repo.attachManuscript(
      thesisId: 't1',
      leaderUid: 'l1',
      storagePath: 'theses/t1/manuscript/abc.pdf',
      fileUrl: 'https://example.test/abc.pdf',
      abstract: '  Fish were counted.  ',
    );

    final t = await repo.watchThesis('t1').first;
    expect(t!.hasManuscript, isTrue);
    expect(t.manuscriptPath, 'theses/t1/manuscript/abc.pdf');
    // Trimmed, because a leading newline in a published abstract is
    // permanent.
    expect(t.manuscriptAbstract, 'Fish were counted.');
  });

  // Every check below is ALSO a rule. fake_cloud_firestore enforces none
  // of them, so without these the whole Dart suite would pass against
  // writes production denies.
  test('only the thesis leader may attach one', () async {
    final repo = ThesisRepository(await seed());
    expect(
      () => repo.attachManuscript(
        thesisId: 't1', leaderUid: 'someone-else',
        storagePath: 'p', fileUrl: 'u', abstract: 'a'),
      throwsA(isA<StateError>()),
    );
  });

  test('an empty abstract is refused', () async {
    final repo = ThesisRepository(await seed());
    expect(
      () => repo.attachManuscript(
        thesisId: 't1', leaderUid: 'l1',
        storagePath: 'p', fileUrl: 'u', abstract: '   '),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an empty storage path is refused', () async {
    final repo = ThesisRepository(await seed());
    expect(
      () => repo.attachManuscript(
        thesisId: 't1', leaderUid: 'l1',
        storagePath: '', fileUrl: 'u', abstract: 'a'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a whitespace-only storage path is refused', () async {
    final repo = ThesisRepository(await seed());
    expect(
      () => repo.attachManuscript(
        thesisId: 't1', leaderUid: 'l1',
        storagePath: '   ', fileUrl: 'u', abstract: 'a'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an empty file URL is refused', () async {
    final repo = ThesisRepository(await seed());
    expect(
      () => repo.attachManuscript(
        thesisId: 't1', leaderUid: 'l1',
        storagePath: 'p', fileUrl: '', abstract: 'a'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a whitespace-only file URL is refused', () async {
    final repo = ThesisRepository(await seed());
    expect(
      () => repo.attachManuscript(
        thesisId: 't1', leaderUid: 'l1',
        storagePath: 'p', fileUrl: '   ', abstract: 'a'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an archived thesis will not take a new manuscript', () async {
    final repo = ThesisRepository(await seed(status: 'archived'));
    expect(
      () => repo.attachManuscript(
        thesisId: 't1', leaderUid: 'l1',
        storagePath: 'p', fileUrl: 'u', abstract: 'a'),
      throwsA(isA<StateError>()),
    );
  });

  test('a missing thesis is a clear error, not a silent no-op', () async {
    final repo = ThesisRepository(await seed());
    expect(
      () => repo.attachManuscript(
        thesisId: 'nope', leaderUid: 'l1',
        storagePath: 'p', fileUrl: 'u', abstract: 'a'),
      throwsA(isA<StateError>()),
    );
  });

  test('re-uploading replaces the manuscript', () async {
    final db = await seed();
    final repo = ThesisRepository(db);

    await repo.attachManuscript(
      thesisId: 't1', leaderUid: 'l1',
      storagePath: 'first.pdf', fileUrl: 'https://x/first.pdf',
      abstract: 'One.');
    await repo.attachManuscript(
      thesisId: 't1', leaderUid: 'l1',
      storagePath: 'second.pdf', fileUrl: 'https://x/second.pdf',
      abstract: 'Two.');

    final t = await repo.watchThesis('t1').first;
    expect(t!.manuscriptPath, 'second.pdf');
    expect(t.manuscriptAbstract, 'Two.');
  });
}
