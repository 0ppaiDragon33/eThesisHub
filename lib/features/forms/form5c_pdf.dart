import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _labelStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
const _valueStyle = pw.TextStyle(fontSize: 10.5);
const _promptStyle = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600);
const _sectionHeaderStyle = pw.TextStyle(
  fontSize: 11,
  fontWeight: pw.FontWeight.bold,
  color: formAccent,
);

/// A "Label: value" row. When [value] is null or empty, a ruled blank
/// prints instead — the printed form rules a line for fields the app does
/// not hold (D60, D61), never the literal string "null" or a silent gap.
pw.Widget _field(String label, String? value) {
  final hasValue = value != null && value.trim().isNotEmpty;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 170,
          child: pw.Text('$label:', style: _labelStyle),
        ),
        pw.Expanded(
          child: hasValue
              ? pw.Text(value, style: _valueStyle)
              : pw.Container(
                  height: 11,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.grey400),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

/// One rubric row: label + weight, the prompt (Section A only), the score
/// out of the weight, and a comment line where one was written (Section A
/// only — Section B takes neither on the printed form).
pw.Widget _criterionRow(Form5cData data, EvaluationCriterion c) {
  final score = data.scores[c.key] ?? 0;
  final comment = c.takesComment ? data.comments[c.key] : null;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                '${c.label} (${c.weight}%)',
                style: const pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text('$score / ${c.weight}', style: _valueStyle),
          ],
        ),
        if (c.takesComment && c.prompt.isNotEmpty)
          pw.Text(c.prompt, style: _promptStyle),
        if (comment != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text('Comment: $comment', style: _promptStyle),
          ),
      ],
    ),
  );
}

pw.Widget _summaryRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: _valueStyle),
        pw.Text(value, style: _valueStyle),
      ],
    ),
  );
}

/// Generates Form 5c — Evaluation Guide — one panelist's completed scoring
/// sheet, as a PDF. `compress: false` keeps the content streams
/// text-greppable; see `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm5cPdf(Form5cData data) async {
  final doc = pw.Document(compress: false);

  final contentCriteria = evaluationCriteria
      .where((c) => c.section == EvaluationSection.content)
      .toList();
  final presentationCriteria = evaluationCriteria
      .where((c) => c.section == EvaluationSection.presentation)
      .toList();

  final presentedOn = data.presentedOn;

  doc.addPage(
    // MultiPage, not Page: eleven criteria with prompts and comments will
    // not fit one sheet. See form1_pdf.dart for why Page silently clips.
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => [
        formChrome(
          rdCode: 'RD-37-06/24-04',
          formTitle: 'Form 5c. Evaluation Guide',
        ),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'EVALUATION GUIDE',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'FOR REPORTS ON RESEARCHES AND TECHNICAL PAPERS',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // D60: the 5b-style identifying header the printed 5c lacks.
        _field('Name of Presenter', data.presenterNames.join(', ')),
        // D61: the app holds neither. Ruled blank.
        _field('Degree and Field of Specialization', null),
        _field(
          'Date of Presentation',
          presentedOn == null
              ? null
              : '${presentedOn.day} ${monthName(presentedOn.month)} '
                  '${presentedOn.year}',
        ),
        _field(
          'Time of Presentation',
          presentedOn == null
              ? null
              : '${presentedOn.hour.toString().padLeft(2, '0')}:'
                  '${presentedOn.minute.toString().padLeft(2, '0')}',
        ),
        _field('Venue', data.venue),
        _field('Title of the Study', data.title),
        _field('Defence', data.defenceType.label),
        _field('Evaluator', data.evaluatorName),
        // D61: the app holds neither. Ruled blank.
        _field('Academic Rank', null),
        _field('Field of Specialization', data.evaluatorField),

        pw.SizedBox(height: 14),
        pw.Container(height: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 8),

        pw.Text('A. CONTENT (50%)', style: _sectionHeaderStyle),
        pw.SizedBox(height: 4),
        for (final c in contentCriteria) _criterionRow(data, c),

        pw.SizedBox(height: 8),
        pw.Text(
          'B. PRESENTATION AND DEFENSE (50%)',
          style: _sectionHeaderStyle,
        ),
        pw.SizedBox(height: 4),
        for (final c in presentationCriteria) _criterionRow(data, c),

        pw.SizedBox(height: 14),
        pw.Container(height: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 8),
        pw.Text(
          'SUMMARY',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _summaryRow('A. CONTENT', '${data.sectionATotal}'),
        _summaryRow('B. PRESENTATION AND DEFENSE', '${data.sectionBTotal}'),
        // D62: M4 deliberately does not compute this. A labelled blank line
        // says so; deleting the row would silently alter the office's form.
        _field('Average Rating', null),
        _summaryRow('Final Grade', '${data.finalGrade}'),
        pw.SizedBox(height: 6),
        pw.Text(
          'Rating (§8a): ${data.rating?.label ?? '—'}',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  return doc.save();
}
