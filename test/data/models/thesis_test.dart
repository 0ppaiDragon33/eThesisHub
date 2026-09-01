import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 14);

  Map<String, dynamic> base() => {
        'leaderUid': 'leader-1',
        'memberNames': ['Bagsain, Karlo June', 'Solinap, Jepte'],
        'workingTitle': 'eThesisHub',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': 'First',
        'academicYear': '2026-2027',
        'status': 'nominationPendingConforme',
        'adviserUid': null,
        'panelistUids': <String>[],
        'createdAt': createdAt,
      };

  test('parses all fields', () {
    final t = Thesis.fromMap('t1', base());
    expect(t.id, 't1');
    expect(t.leaderUid, 'leader-1');
    expect(t.memberNames, hasLength(2));
    expect(t.status, ThesisStatus.nominationPendingConforme);
    expect(t.panelistUids, isEmpty);
  });

  test('unknown status degrades to draft', () {
    final t = Thesis.fromMap('t2', {...base(), 'status': 'wat'});
    expect(t.status, ThesisStatus.draft);
  });

  test('toMap round-trips', () {
    final restored = Thesis.fromMap('t3', Thesis.fromMap('t3', base()).toMap());
    expect(restored.academicYear, '2026-2027');
    expect(restored.memberNames, contains('Solinap, Jepte'));
  });

  test('nominationsSubmittedAt defaults to null when absent', () {
    final t = Thesis.fromMap('t4', base());
    expect(t.nominationsSubmittedAt, isNull);
  });

  test('parses a non-null nominationsSubmittedAt', () {
    final submittedAt = DateTime.utc(2026, 8, 15, 9, 30);
    final t = Thesis.fromMap(
        't5', {...base(), 'nominationsSubmittedAt': submittedAt});
    expect(t.nominationsSubmittedAt, submittedAt);
  });

  test('toMap round-trips nominationsSubmittedAt', () {
    final submittedAt = DateTime.utc(2026, 8, 15, 9, 30);
    final original =
        Thesis.fromMap('t6', {...base(), 'nominationsSubmittedAt': submittedAt});
    final restored = Thesis.fromMap('t6', original.toMap());
    expect(restored.nominationsSubmittedAt, submittedAt);
  });

  // The lifecycle in the design doc has always ended `-> archived`, and the
  // enum has never had it. Adding it makes thesisStage()'s exhaustive
  // switch fail to compile until handled -- which is the safety net that
  // function's own comment describes.
  test('archived is a real status and buckets to its own stage', () {
    expect(ThesisStatus.fromString('archived'), ThesisStatus.archived);
    expect(thesisStage(ThesisStatus.archived), ThesisStage.archived);
    expect(ThesisStage.archived.label, 'Archived');
  });

  test('a thesis with no manuscript reads as absent, not as an error', () {
    final t = Thesis.fromMap('t1', {
      'leaderUid': 'l1',
      'memberNames': <String>['A Student'],
      'workingTitle': 'T',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': 'titleApproved',
      'panelistUids': <String>[],
      'createdAt': DateTime(2026, 8, 1),
    });

    expect(t.manuscriptPath, isNull);
    expect(t.manuscriptUrl, isNull);
    expect(t.manuscriptAbstract, isNull);
    expect(t.manuscriptUploadedAt, isNull);
    expect(t.hasManuscript, isFalse);
  });

  test('a thesis with a manuscript reads all four fields back', () {
    final t = Thesis.fromMap('t1', {
      'leaderUid': 'l1',
      'memberNames': <String>['A Student'],
      'workingTitle': 'T',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': 'titleApproved',
      'panelistUids': <String>[],
      'createdAt': DateTime(2026, 8, 1),
      'manuscriptPath': 'theses/t1/manuscript/abc.pdf',
      'manuscriptUrl': 'https://example.test/abc.pdf',
      'manuscriptAbstract': 'A study of things.',
      'manuscriptUploadedAt': DateTime(2026, 9, 25),
    });

    expect(t.manuscriptPath, 'theses/t1/manuscript/abc.pdf');
    expect(t.manuscriptUrl, 'https://example.test/abc.pdf');
    expect(t.manuscriptAbstract, 'A study of things.');
    expect(t.manuscriptUploadedAt, DateTime(2026, 9, 25));
    expect(t.hasManuscript, isTrue);
  });

  // A URL with no path (or the reverse) is a half-written upload, not a
  // manuscript. hasManuscript must not report one.
  test('a half-written manuscript does not count as having one', () {
    Thesis withOnly(Map<String, dynamic> extra) => Thesis.fromMap('t1', {
          'leaderUid': 'l1',
          'memberNames': <String>[],
          'workingTitle': 'T',
          'college': 'CICT',
          'program': 'BSIT',
          'semester': 'First',
          'academicYear': '2026-2027',
          'status': 'titleApproved',
          'panelistUids': <String>[],
          'createdAt': DateTime(2026, 8, 1),
          ...extra,
        });

    expect(withOnly({'manuscriptUrl': 'https://x'}).hasManuscript, isFalse);
    expect(withOnly({'manuscriptPath': 'p'}).hasManuscript, isFalse);
  });
}
