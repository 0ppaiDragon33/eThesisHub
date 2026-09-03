import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/archive_entry.dart';

ArchiveEntry entry({
  String title = 'A Study of Coastal Fisheries in Barotac Nuevo',
  List<String> members = const ['Santos, J.', 'Bautista, M.'],
  String adviser = 'Dr. Zamora',
}) {
  return ArchiveEntry.fromMap('t1', {
    'title': title,
    'memberNames': members,
    'abstract': 'Fish were counted.',
    'college': 'CICT',
    'program': 'BSIT',
    'academicYear': '2026-2027',
    'adviserName': adviser,
    'panelNames': <String>['Dr. Reyes', 'Dr. Lim'],
    'manuscriptUrl': 'https://example.test/m.pdf',
    'manuscriptPath': 'theses/t1/manuscript/m.pdf',
    'finalDefenceId': 'd9',
    'uploadedBy': 'l1',
    'archivedBy': 'c1',
    'archivedAt': DateTime(2026, 9, 30),
  });
}

void main() {
  test('fromMap reads every published field', () {
    final e = entry();
    expect(e.thesisId, 't1');
    expect(e.title, 'A Study of Coastal Fisheries in Barotac Nuevo');
    expect(e.memberNames, ['Santos, J.', 'Bautista, M.']);
    expect(e.abstract, 'Fish were counted.');
    expect(e.adviserName, 'Dr. Zamora');
    expect(e.panelNames, ['Dr. Reyes', 'Dr. Lim']);
    expect(e.finalDefenceId, 'd9');
    expect(e.archivedBy, 'c1');
    expect(e.archivedAt, DateTime(2026, 9, 30));
  });

  test('authorsLabel joins the members for a card', () {
    expect(entry().authorsLabel, 'Santos, J., Bautista, M.');
  });

  // THE test for D54. Firestore matches prefixes only, which is why search
  // runs in Dart at all -- so mid-string must work, or the whole decision
  // was pointless.
  test('search matches mid-string, not just the start', () {
    expect(entry().matches('fisheries'), isTrue);
    expect(entry().matches('Barotac'), isTrue);
  });

  test('search is case-insensitive and trims the query', () {
    expect(entry().matches('  COASTAL '), isTrue);
  });

  test('search covers author names as well as the title', () {
    expect(entry().matches('bautista'), isTrue);
    expect(entry().matches('Zamora'), isFalse,
        reason: 'D55 narrows search to title and AUTHOR, not adviser');
  });

  // D55: the abstract is displayed but not searched.
  test('search does not reach the abstract', () {
    expect(entry().matches('counted'), isFalse);
  });

  test('an empty query matches everything', () {
    expect(entry().matches(''), isTrue);
    expect(entry().matches('   '), isTrue);
  });

  test('a missing optional field reads as empty rather than throwing', () {
    final e = ArchiveEntry.fromMap('t2', const {});
    expect(e.title, '');
    expect(e.memberNames, isEmpty);
    expect(e.panelNames, isEmpty);
    expect(e.archivedAt, isNull);
  });
}
