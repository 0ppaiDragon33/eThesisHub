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
}
