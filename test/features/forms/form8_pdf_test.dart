import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form8_pdf.dart';

import 'pdf_text.dart';

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
  test('carries the chrome and the form title', () async {
    final text = extractPdfText(
        await buildForm8Pdf(Form8Data.assemble(entry: entry())));

    expect(text, contains('RD-39-06/24-04'));
    expect(text, contains('Form 8. Certification of Submission of Bound Copies'));
    expect(text, contains('ILOILO STATE UNIVERSITY'));
  });

  test('prints the certification sentence with the names and the title',
      () async {
    final text = extractPdfText(
        await buildForm8Pdf(Form8Data.assemble(entry: entry())));

    expect(text, contains('CERTIFICATION'));
    expect(text, contains('This is to certify that'));
    expect(text, contains('Santos, J.'));
    expect(text, contains('Lim, K.'));
    expect(text, contains('has submitted bound copies'));
    expect(text, contains('A Study of Coastal Fisheries'));
  });

  test('prints the issue date', () async {
    final text = extractPdfText(await buildForm8Pdf(
        Form8Data.assemble(entry: entry(archivedAt: DateTime(2026, 9, 30)))));

    expect(text, contains('30'));
    expect(text, contains('September'));
    expect(text, contains('2026'));
  });

  // D66: the printed form ends in a ruled line for a wet signature, so
  // `archivedBy` is never resolved to a name.
  test('rules a blank signature line labelled for the coordinator',
      () async {
    final text = extractPdfText(
        await buildForm8Pdf(Form8Data.assemble(entry: entry())));

    expect(text, contains('Research Coordinator'));
    expect(text, isNot(contains('c1')));
  });

  test('a one-member group reads naturally', () async {
    final text = extractPdfText(await buildForm8Pdf(
        Form8Data.assemble(entry: entry(members: const ['Solo, S.']))));

    expect(text, contains('Solo, S.'));
    expect(text, contains('has submitted bound copies'));
  });

  // `issuedOn` is nullable (it comes straight from `archivedAt`, which
  // `ArchiveEntry.fromMap` leaves null when the map omits it). The renderer
  // must rule a blank rather than print the literal string "null" on a
  // certification — that's the failure the ruled blank exists to prevent.
  test('a null issue date rules a blank rather than printing "null"',
      () async {
    final data = Form8Data(
      studentNames: const ['Santos, J.', 'Lim, K.'],
      title: 'A Study of Coastal Fisheries',
      issuedOn: null,
    );

    final bytes = await buildForm8Pdf(data);
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
    // The "Date" caption is unconditional text under the date block, so its
    // presence rules out the block being omitted wholesale when the date is
    // null — distinct from merely not printing "null" in its place.
    expect(text, contains('Date'));
  });

  group('buildForm8Blank', () {
    // Requirement test 3, first direction: the blank renders and carries
    // the template marking. §6's Form8Unissuable exists precisely because
    // a blank-looking certificate reads as official -- this is the mark
    // that keeps a printed blank from being that.
    test('renders and contains the template marking', () async {
      final bytes = await buildForm8Blank();
      final text = extractPdfText(bytes);

      expect(bytes, isNotEmpty);
      expect(text, contains('RD-39-06/24-04'));
      expect(text, contains('CERTIFICATION'));
      expect(text, contains('BLANK TEMPLATE'));
      expect(text, contains('not an issued certification'));
      expect(text, contains('TEMPLATE'));
    });
  });

  // Requirement test 3, second direction: a real, filled certificate must
  // never carry the marking a blank does -- the two must not contradict
  // each other.
  test('a filled certificate does not contain the template marking',
      () async {
    final text = extractPdfText(
        await buildForm8Pdf(Form8Data.assemble(entry: entry())));

    expect(text, isNot(contains('BLANK TEMPLATE')));
    expect(text, isNot(contains('TEMPLATE')));
    expect(text, isNot(contains('not an issued certification')));
  });
}
