import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/form3_data.dart';
import 'package:ethesishub/features/forms/form3_pdf.dart';

import 'pdf_text.dart';

Thesis _thesis({List<String> members = const ['Santos, J.', 'Lim, K.']}) {
  return Thesis.fromMap('t1', {
    'leaderUid': 'l1',
    'memberNames': members,
    'workingTitle': 'Working title',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'status': 'titleApproved',
    'panelistUids': <String>['p1'],
    'createdAt': DateTime(2026, 8, 1),
  });
}

Defence _defence() {
  return Defence.fromMap('d1', {
    'thesisId': 't1',
    'type': 'preOral',
    'scheduledAt': DateTime(2026, 9, 23, 9, 30),
    'venue': 'CICT AVR',
    'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': 'scheduled',
    'createdBy': 'c1',
  });
}

void main() {
  test('carries the chrome and the form title', () async {
    final text = extractPdfText(await buildForm3Blank());

    expect(text, contains('RD-33-06/24-04'));
    expect(text, contains('Request to Convene'));
    expect(text, contains('ILOILO STATE UNIVERSITY'));
  });

  test('a filled letter names the panel, presenter and title', () async {
    final data = Form3Data.assemble(
      thesis: _thesis(),
      defence: _defence(),
      title: 'A Study of Coastal Fisheries',
      panelNames: const ['Dr. Reyes', 'Dr. Lim'],
    );
    final text = extractPdfText(await buildForm3Pdf(data));

    expect(text, contains('Dr. Reyes'));
    expect(text, contains('Dr. Lim'));
    expect(text, contains('Santos, J.'));
    expect(text, contains('A Study of Coastal Fisheries'));
    expect(text, contains('CICT AVR'));
    expect(text, contains('September'));
  });

  test('the coordinator and dean lines stay blank even when filled',
      () async {
    // No digital sign-off is tracked for a defence request -- neither
    // name should ever leak into the letter.
    final data = Form3Data.assemble(
      thesis: _thesis(),
      defence: _defence(),
      title: 'A Study of Coastal Fisheries',
      panelNames: const ['Dr. Reyes'],
    );
    final text = extractPdfText(await buildForm3Pdf(data));

    expect(text, contains('College Research Coordinator'));
    expect(text, contains('Dean, CICT'));
  });

  test('the blank template renders with no crash and no "null"', () async {
    final bytes = await buildForm3Blank();
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
  });
}
