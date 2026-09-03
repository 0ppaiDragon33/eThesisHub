import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/form5a_data.dart';
import 'package:ethesishub/features/forms/form5a_pdf.dart';

import 'pdf_text.dart';

Thesis _thesis() {
  return Thesis.fromMap('t1', {
    'leaderUid': 'l1',
    'memberNames': <String>['Santos, J.', 'Lim, K.'],
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
    'type': 'final',
    'scheduledAt': DateTime(2026, 10, 5, 14),
    'venue': 'CICT AVR 2',
    'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': 'scheduled',
    'createdBy': 'c1',
  });
}

void main() {
  test('carries the chrome and the form title', () async {
    final text = extractPdfText(await buildForm5aBlank());

    expect(text, contains('RD-36-06/24-04'));
    expect(text, contains('Request for Final Oral Defense'));
  });

  test('a filled letter names the thesis, date, place and time', () async {
    final data = Form5aData.assemble(
      thesis: _thesis(),
      defence: _defence(),
      title: 'A Study of Coastal Fisheries',
    );
    final text = extractPdfText(await buildForm5aPdf(data));

    expect(text, contains('A Study of Coastal Fisheries'));
    expect(text, contains('CICT AVR 2'));
    expect(text, contains('October'));
    expect(text, contains('14:00'));
  });

  test('the blank template renders with no crash and no "null"', () async {
    final bytes = await buildForm5aBlank();
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
  });
}
