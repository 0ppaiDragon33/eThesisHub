import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/form7_data.dart';
import 'package:ethesishub/features/forms/form7_pdf.dart';

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

void main() {
  test('carries the chrome and the form title', () async {
    final text = extractPdfText(await buildForm7Blank());

    expect(text, contains('RD-38-06/24-04'));
    expect(text, contains('Certificate of Review'));
    expect(text, contains('CERTIFICATION OF REVIEW'));
  });

  test('a filled certificate names the presenter and the title', () async {
    final data = Form7Data.assemble(
      thesis: _thesis(),
      title: 'A Study of Coastal Fisheries',
    );
    final text = extractPdfText(await buildForm7Pdf(data));

    expect(text, contains('Santos, J.'));
    expect(text, contains('Lim, K.'));
    expect(text, contains('A Study of Coastal Fisheries'));
  });

  // D (this form): the review table lists a fixed seven roles and is
  // never prefilled, filled certificate or not -- two of the roles
  // (Grammarian, Statistician) aren't modelled anywhere in this app.
  test('the review table always lists all seven roles, unfilled', () async {
    final filled = extractPdfText(await buildForm7Pdf(Form7Data.assemble(
        thesis: _thesis(), title: 'A Study of Coastal Fisheries')));
    final blank = extractPdfText(await buildForm7Blank());

    for (final role in [
      'Dean',
      'Research Coordinator',
      'Thesis Adviser',
      'Grammarian',
      'Statistician',
    ]) {
      expect(filled, contains(role), reason: role);
      expect(blank, contains(role), reason: role);
    }
    expect(filled, contains('Panel Member'));
    expect(filled, contains('Approved'));
    expect(filled, contains('Remarks'));
  });

  test('the blank template renders with no crash and no "null"', () async {
    final bytes = await buildForm7Blank();
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
  });
}
