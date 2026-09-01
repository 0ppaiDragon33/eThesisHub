import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/features/forms/form8_data.dart';

ArchiveEntry entry({
  List<String> members = const ['Santos, J.', 'Lim, K.'],
  String title = 'A Study of Coastal Fisheries',
  DateTime? archivedAt,
}) {
  return ArchiveEntry.fromMap('t1', {
    'title': title,
    'memberNames': members,
    'abstract': 'Fish were counted.',
    'college': 'CICT',
    'program': 'BSIT',
    'academicYear': '2026-2027',
    'adviserName': 'Dr. Zamora',
    'panelNames': <String>['Dr. Reyes'],
    'manuscriptUrl': 'https://example.test/m.pdf',
    'manuscriptPath': 'p/m.pdf',
    'finalDefenceId': 'd9',
    'uploadedBy': 'l1',
    'archivedBy': 'c1',
    'archivedAt': archivedAt ?? DateTime(2026, 9, 30),
  });
}

void main() {
  // D64: read from the ARCHIVE ENTRY, not the thesis. The entry is the
  // record the certificate attests to, and it is already frozen.
  test('takes its three fields from the archive entry', () {
    final d = Form8Data.assemble(entry: entry());

    expect(d.studentNames, ['Santos, J.', 'Lim, K.']);
    expect(d.title, 'A Study of Coastal Fisheries');
    expect(d.issuedOn, DateTime(2026, 9, 30));
  });

  // D65: the printed form says "his/her", singular, but a thesis here
  // belongs to a group and the deposit was joint.
  test('names every member of the group, not just the leader', () {
    final d = Form8Data.assemble(
        entry: entry(members: const ['A', 'B', 'C']));
    expect(d.studentNames, hasLength(3));
  });

  test('a one-member group needs no special case', () {
    expect(Form8Data.assemble(entry: entry(members: const ['Solo, S.']))
        .studentNames, ['Solo, S.']);
  });
}
