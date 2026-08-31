import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/archive_repository.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

Thesis thesisWith({String id = 't1'}) => Thesis.fromMap(id, {
      'leaderUid': 'l1',
      'adviserUid': 'a1',
      'panelistUids': <String>['p1', 'p2'],
      'memberNames': <String>['Santos, J.', 'Bautista, M.'],
      'workingTitle': 'Working',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': 'titleApproved',
      'createdAt': DateTime(2026, 8, 1),
      'manuscriptPath': 'theses/$id/manuscript/abc.pdf',
      'manuscriptUrl': 'https://example.test/$id.pdf',
      'manuscriptAbstract': 'Fish were counted.',
      'manuscriptUploadedAt': DateTime(2026, 9, 25),
    });

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1',
    'panelistUids': <String>['p1', 'p2'],
    'memberNames': <String>['Santos, J.', 'Bautista, M.'],
    'workingTitle': 'Working', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
    'status': 'titleApproved',
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    'manuscriptPath': 'theses/t1/manuscript/abc.pdf',
    'manuscriptUrl': 'https://example.test/t1.pdf',
    'manuscriptAbstract': 'Fish were counted.',
  });
  return db;
}

Future<void> publishOne(ArchiveRepository repo, {String id = 't1'}) {
  return repo.publish(
    thesis: thesisWith(id: id),
    title: 'A Study of Coastal Fisheries',
    adviserName: 'Dr. Zamora',
    panelNames: const ['Dr. Reyes', 'Dr. Lim'],
    finalDefenceId: 'd9',
    coordinatorUid: 'c1',
  );
}

void main() {
  test('publishing writes the entry AND archives the thesis', () async {
    final db = await seed();
    final repo = ArchiveRepository(db);

    await publishOne(repo);

    final entry = await repo.watchEntry('t1').first;
    expect(entry!.title, 'A Study of Coastal Fisheries');
    expect(entry.adviserName, 'Dr. Zamora');
    expect(entry.panelNames, ['Dr. Reyes', 'Dr. Lim']);
    expect(entry.abstract, 'Fish were counted.');
    expect(entry.manuscriptUrl, 'https://example.test/t1.pdf');
    expect(entry.archivedBy, 'c1');

    // Both writes, or the archive and the thesis disagree about whether
    // this thesis is published.
    final thesis = await ThesisRepository(db).watchThesis('t1').first;
    expect(thesis!.status, ThesisStatus.archived);
  });

  test('a thesis with no manuscript cannot be published', () async {
    final db = await seed();
    await db.collection('theses').doc('t1').update({
      'manuscriptPath': FieldValue.delete(),
      'manuscriptUrl': FieldValue.delete(),
    });
    final repo = ArchiveRepository(db);

    expect(
      () => repo.publish(
        thesis: Thesis.fromMap('t1', {
          'leaderUid': 'l1', 'memberNames': <String>[], 'workingTitle': 'W',
          'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
          'academicYear': '2026-2027', 'status': 'titleApproved',
          'panelistUids': <String>[], 'createdAt': DateTime(2026, 8, 1),
        }),
        title: 'T', adviserName: 'Dr. Z', panelNames: const [],
        finalDefenceId: 'd9', coordinatorUid: 'c1'),
      throwsA(isA<StateError>()),
    );
  });

  test('publishing twice is refused', () async {
    final db = await seed();
    final repo = ArchiveRepository(db);
    await publishOne(repo);

    expect(() => publishOne(repo), throwsA(isA<StateError>()));
  });

  test('a correction changes the title and leaves the manuscript alone',
      () async {
    final db = await seed();
    final repo = ArchiveRepository(db);
    await publishOne(repo);

    await repo.correct(thesisId: 't1', title: 'Corrected Title');

    final entry = await repo.watchEntry('t1').first;
    expect(entry!.title, 'Corrected Title');
    expect(entry.manuscriptUrl, 'https://example.test/t1.pdf');
  });

  test('retracting removes the entry', () async {
    final db = await seed();
    final repo = ArchiveRepository(db);
    await publishOne(repo);

    await repo.retract('t1');

    expect(await repo.watchEntry('t1').first, isNull);
    expect(await repo.watchArchive().first, isEmpty);
  });

  // RULING: the brief's original version of this test wrote three entries
  // through publish() and asserted only hasLength(3) -- which an unsorted
  // implementation also satisfies, and which cannot be fixed by varying
  // publish order because archivedAt comes from FieldValue.serverTimestamp()
  // and so is indistinguishable across three publishes in one test.
  //
  // This version writes directly into the `archive` collection, bypassing
  // publish() entirely, with distinct explicit archivedAt values, inserted
  // in an order that is NOT the expected output order. fake_cloud_firestore
  // returns documents in INSERTION order, so if this test's insertion order
  // already matched "newest first" it would pass against an implementation
  // that never sorts at all. It does not: t-old is inserted before t-new.
  test('the archive comes back newest first', () async {
    final db = FakeFirebaseFirestore();

    Map<String, dynamic> entry(DateTime archivedAt) => {
          'title': 'T', 'memberNames': <String>[], 'abstract': 'a',
          'college': 'CICT', 'program': 'BSIT', 'academicYear': '2026-2027',
          'adviserName': 'Dr. Z', 'panelNames': <String>[],
          'manuscriptUrl': 'u', 'manuscriptPath': 'p',
          'finalDefenceId': 'd', 'uploadedBy': 'l1',
          'uploadedAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
          'archivedBy': 'c1',
          'archivedAt': Timestamp.fromDate(archivedAt),
        };

    // Insertion order: middle, oldest, newest -- deliberately not the
    // expected newest-first output order (newest, middle, oldest).
    await db
        .collection('archive')
        .doc('t-middle')
        .set(entry(DateTime(2026, 6, 15)));
    await db
        .collection('archive')
        .doc('t-old')
        .set(entry(DateTime(2026, 1, 1)));
    await db
        .collection('archive')
        .doc('t-new')
        .set(entry(DateTime(2026, 9, 1)));

    final repo = ArchiveRepository(db);
    final all = await repo.watchArchive().first;

    expect(all.map((e) => e.thesisId).toList(),
        ['t-new', 't-middle', 't-old']);
  });

  test('an empty archive is an empty list, not an error', () async {
    expect(await ArchiveRepository(await seed()).watchArchive().first,
        isEmpty);
  });
}
