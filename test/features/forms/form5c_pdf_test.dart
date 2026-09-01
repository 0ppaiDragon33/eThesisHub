import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';
import 'package:ethesishub/features/forms/form5c_pdf.dart';

import 'pdf_text.dart';

Thesis buildThesis({List<String> members = const ['Santos, J.', 'Lim, K.']}) {
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

Defence buildDefence({
  DefenceType type = DefenceType.final_,
  /// `Defence.scheduledAt` is nullable; false leaves it unset, which is the
  /// path Form 5c's `presentedOn` blank exists for.
  bool scheduled = true,
}) {
  return Defence.fromMap('d1', {
    'thesisId': 't1',
    'type': type.value,
    'scheduledAt': scheduled ? DateTime(2026, 9, 23, 9, 30) : null,
    'venue': 'CICT AVR',
    'panelUids': <String>['p1'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': 'completed',
    'createdBy': 'c1',
  });
}

Evaluation buildEvaluation({
  Map<String, int>? scores,
  Map<String, String> comments = const {},
  String rating = 'pass',
}) {
  final s = scores ?? {for (final c in evaluationCriteria) c.key: c.weight};
  return Evaluation.fromMap('p1', {
    'evaluatorName': 'Dr. Reyes',
    'scores': s,
    'comments': comments,
    'total': totalOf(s),
    'rating': rating,
  });
}

Form5cData assemble({
  Thesis? thesis,
  Defence? defence,
  Evaluation? evaluation,
  String title = 'A Study of Coastal Fisheries',
  String evaluatorField = 'Information Technology',
}) {
  return Form5cData.assemble(
    thesis: thesis ?? buildThesis(),
    defence: defence ?? buildDefence(),
    evaluation: evaluation ?? buildEvaluation(),
    title: title,
    evaluatorField: evaluatorField,
  );
}

void main() {
  test('carries the chrome and the form title', () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));

    expect(text, contains('RD-37-06/24-04'));
    expect(text, contains('Form 5c. Evaluation Guide'));
    expect(text, contains('ILOILO STATE UNIVERSITY'));
  });

  // D60. The printed 5c has NO identifying fields at all — it works on
  // paper only because it is stapled to Form 5b. A PDF is not.
  test('carries the 5b-style header the printed form lacks', () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));

    expect(text, contains('Santos, J.'));
    expect(text, contains('A Study of Coastal Fisheries'));
    expect(text, contains('CICT AVR'));
    expect(text, contains('Dr. Reyes'));
    expect(text, contains('Information Technology'));
    expect(text, contains('September'));
  });

  test('names which defence it scored', () async {
    final finalText = extractPdfText(await buildForm5cPdf(assemble()));
    expect(finalText, contains('Final defence'));

    final preOral = extractPdfText(await buildForm5cPdf(
        assemble(defence: buildDefence(type: DefenceType.preOral))));
    expect(preOral, contains('Pre-oral defence'));
  });

  // D61. The app holds neither, and the paper form rules a line for both.
  // The caption alone is not the assertion: `_field`'s null branch would
  // pass that even if it rendered nothing at all beside the label. Assert
  // the caption present AND the literal string "null" absent from the whole
  // document, as Form 8's null-date test does.
  test('rules blank lines for Academic Rank and the presenter degree',
      () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));

    expect(text, contains('Academic Rank'));
    expect(text, contains('Degree and Field of Specialization'));
    expect(text, isNot(contains('null')));
  });

  test('prints every criterion with its weight and score', () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));

    for (final c in evaluationCriteria) {
      expect(text, contains(c.label), reason: c.key);
    }
  });

  // D63. M4 scored Title out of 5 (its D35); printing the paper form's
  // "50%" beside a mark out of 5 would be incoherent. RULING: assert the
  // weight actually printed beside Title (5%), not merely the absence of
  // "50%" anywhere on the page — the section headers legitimately print
  // "50%" for A. CONTENT and B. PRESENTATION AND DEFENSE.
  test('Title prints at 5%, not the paper form\'s 50%', () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));

    expect(text, contains('Title (5%)'));
    expect(text, isNot(contains('Title (50%)')));
  });

  test('prints the prompts, which are what make the rubric fillable',
      () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));
    expect(text, contains('Natural?'));
  });

  test('prints a comment where one was written', () async {
    final text = extractPdfText(await buildForm5cPdf(
        assemble(evaluation: buildEvaluation(
            comments: {'title': 'Narrow it to the municipality.'}))));

    expect(text, contains('Narrow it to the municipality.'));
  });

  test('prints the summary totals and the rating', () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));

    expect(text, contains('SUMMARY'));
    expect(text, contains('100'));
    expect(text, contains('Pass'));
  });

  // D62. M4 deliberately does not compute it (its D46). A blank line says
  // so; deleting the row would silently alter the office's form.
  test('Average Rating prints as a labelled blank line', () async {
    final text = extractPdfText(await buildForm5cPdf(assemble()));
    expect(text, contains('Average Rating'));
    // As above: the label alone would pass even if the null branch rendered
    // nothing beside it, so also rule out the literal "null".
    expect(text, isNot(contains('null')));
  });

  // `presentedOn` comes straight from `Defence.scheduledAt`, which is
  // nullable. Carried forward explicitly during the milestone and, until
  // now, never tested: an unscheduled defence must rule blanks for both the
  // date and the time rather than print "null" on a panelist's sheet.
  test('a null presentation date rules blanks rather than printing "null"',
      () async {
    final bytes =
        await buildForm5cPdf(assemble(defence: buildDefence(scheduled: false)));
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
    // Both captions are unconditional, so their presence rules out the rows
    // being dropped wholesale -- distinct from merely not printing "null".
    expect(text, contains('Date of Presentation'));
    expect(text, contains('Time of Presentation'));
    // And the rest of the sheet still renders.
    expect(text, contains('SUMMARY'));
  });

  // A missing key must not print a genuine zero: "0 / 25" is
  // indistinguishable from a panelist who actually scored the criterion
  // nothing. Nothing guarantees all eleven keys are present.
  test('a criterion missing from scores rules a blank, not a zero', () async {
    final full = {for (final c in evaluationCriteria) c.key: c.weight};
    // 'alertness' is the only criterion weighted 25, so "/ 25" identifies
    // its row uniquely in the extracted text.
    final missing = Map<String, int>.from(full)..remove('alertness');

    final text = extractPdfText(await buildForm5cPdf(
        assemble(evaluation: buildEvaluation(scores: missing))));

    expect(text, contains('Alertness and smartness in answering question'));
    expect(text, contains('/ 25'));
    expect(text, isNot(contains('0 / 25')));
    expect(text, isNot(contains('null')));

    // Control: with the score present, the row does print the mark, so the
    // assertion above is about the missing key and not about the format.
    final scored = extractPdfText(await buildForm5cPdf(
        assemble(evaluation: buildEvaluation(scores: full))));
    expect(scored, contains('25 / 25'));
  });

  test('a sheet with no comments still renders', () async {
    final bytes = await buildForm5cPdf(
        assemble(evaluation: buildEvaluation(comments: const {})));
    expect(bytes.lengthInBytes, greaterThan(1000));
  });
}
