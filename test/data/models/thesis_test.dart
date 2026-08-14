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
}
