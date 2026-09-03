import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/form5b_data.dart';
import 'package:ethesishub/features/forms/form5b_pdf.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';

import 'pdf_text.dart';

Thesis _thesis() => Thesis.fromMap('t1', {
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

Defence _defence() => Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'scheduledAt': DateTime(2026, 9, 23, 9, 30),
      'venue': 'CICT AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
    });

Evaluation _evaluation() => Evaluation.fromMap('p1', {
      'evaluatorName': 'Dr. Reyes',
      'scores': {for (final c in evaluationCriteria) c.key: c.weight},
      'comments': const <String, String>{},
      'total': 100,
      'rating': 'pass',
    });

void main() {
  test('carries the chrome and the form title', () async {
    final text = extractPdfText(await buildForm5bBlank());

    expect(text, contains('RD-37-06/24-04'));
    expect(text, contains('Presenter and Evaluator Profile'));
  });

  // Form 5b is a strict subset of the fields Form5cData already resolves
  // -- fromForm5c must carry every one of them through unchanged.
  test('fromForm5c carries every field Form 5c already resolved', () async {
    final c = Form5cData.assemble(
      thesis: _thesis(),
      defence: _defence(),
      evaluation: _evaluation(),
      title: 'A Study of Coastal Fisheries',
      evaluatorField: 'Information Technology',
    );
    final b = Form5bData.fromForm5c(c);
    final text = extractPdfText(await buildForm5bPdf(b));

    expect(text, contains('Santos, J.'));
    expect(text, contains('A Study of Coastal Fisheries'));
    expect(text, contains('CICT AVR'));
    expect(text, contains('Dr. Reyes'));
    expect(text, contains('Information Technology'));
    expect(text, contains('September'));
  });

  test('the blank template rules every field, no "null"', () async {
    final bytes = await buildForm5bBlank();
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
    expect(text, contains('Academic Rank'));
  });
}
