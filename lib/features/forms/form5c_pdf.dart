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

/// The ruled line a missing value prints as. Shared by [_field] and
/// [_criterionRow] so an absent score and an absent header field look the
/// same on the page — both say "the system does not hold this", and neither
/// may be mistaken for a value.
pw.Widget _rule({double? width}) => pw.Container(
      width: width,
      height: 11,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
      ),
    );

/// A "Label: value" row. When [value] is null or empty, a ruled blank
/// prints instead — the printed form rules a line for fields the app does
/// not hold (D60, D61), never the literal string "null" or a silent gap.
/// A blank template (built with no [Form5cData] at all — see
/// [buildForm5cBlank]) rules every one of these the same way: a template
/// is nothing but a page that rules a blank for every field it would
/// otherwise print.
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
          child: hasValue ? pw.Text(value, style: _valueStyle) : _rule(),
        ),
      ],
    ),
  );
}

/// One rubric row: label + weight, the prompt (Section A only), the score
/// out of the weight, and a comment line where one was written (Section A
/// only — Section B takes neither on the printed form).
///
/// Takes [scores]/[comments] directly rather than a whole [Form5cData] so
/// [_page] can pass empty maps for a blank template without fabricating a
/// data object. A criterion absent from [scores] rules a blank rather than
/// printing a mark — that covers both a real evaluation missing a key and
/// the blank template's empty map alike. Defaulting to 0 would render
/// "0 / 25" — a genuine zero, indistinguishable from a panelist who scored
/// the criterion nothing. The denominator still prints, so the row stays a
/// scoring row with a mark to be written in.
pw.Widget _criterionRow(
  Map<String, int> scores,
  Map<String, String> comments,
  EvaluationCriterion c,
) {
  final score = scores[c.key];
  final comment = c.takesComment ? comments[c.key] : null;
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
            if (score == null)
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _rule(width: 26),
                  pw.SizedBox(width: 4),
                  pw.Text('/ ${c.weight}', style: _valueStyle),
                ],
              )
            else
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

/// A "label ... total" summary row. [value] rules a blank exactly as
/// [_field] does, for the same reason — the blank template has no section
/// totals to print, and a genuine total of 0 must not be confused with one.
pw.Widget _summaryRow(String label, int? value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: _valueStyle),
        value == null
            ? _rule(width: 40)
            : pw.Text('$value', style: _valueStyle),
      ],
    ),
  );
}

/// The whole printed page, shared by a real evaluation and the blank
/// template. `data == null` is the template case: every field, every
/// criterion score, and every total rules a blank, using exactly the same
/// blank-rendering `_field`/`_criterionRow`/`_summaryRow` already use for a
/// real evaluation's missing values (D60-D62) — a template is structurally
/// nothing but a page with nothing filled in, so it is the same code, not
/// a parallel layout that could drift from it.
List<pw.Widget> _page({Form5cData? data}) {
  final contentCriteria = evaluationCriteria
      .where((c) => c.section == EvaluationSection.content)
      .toList();
  final presentationCriteria = evaluationCriteria
      .where((c) => c.section == EvaluationSection.presentation)
      .toList();

  final presentedOn = data?.presentedOn;
  final scores = data?.scores ?? const <String, int>{};
  final comments = data?.comments ?? const <String, String>{};

  return [
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
    _field('Name of Presenter', data?.presenterNames.join(', ')),
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
    _field('Venue', data?.venue),
    _field('Title of the Study', data?.title),
    _field('Defence', data?.defenceType.label),
    _field('Evaluator', data?.evaluatorName),
    // D61: the app holds neither. Ruled blank.
    _field('Academic Rank', null),
    _field('Field of Specialization', data?.evaluatorField),

    pw.SizedBox(height: 14),
    pw.Container(height: 1, color: PdfColors.grey400),
    pw.SizedBox(height: 8),

    pw.Text('A. CONTENT (50%)', style: _sectionHeaderStyle),
    pw.SizedBox(height: 4),
    for (final c in contentCriteria) _criterionRow(scores, comments, c),

    pw.SizedBox(height: 8),
    pw.Text(
      'B. PRESENTATION AND DEFENSE (50%)',
      style: _sectionHeaderStyle,
    ),
    pw.SizedBox(height: 4),
    for (final c in presentationCriteria) _criterionRow(scores, comments, c),

    pw.SizedBox(height: 14),
    pw.Container(height: 1, color: PdfColors.grey400),
    pw.SizedBox(height: 8),
    pw.Text(
      'SUMMARY',
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 6),
    _summaryRow('A. CONTENT', data?.sectionATotal),
    _summaryRow('B. PRESENTATION AND DEFENSE', data?.sectionBTotal),
    // D62: M4 deliberately does not compute this. A labelled blank line
    // says so; deleting the row would silently alter the office's form.
    _field('Average Rating', null),
    _summaryRow('Final Grade', data?.finalGrade),
    pw.SizedBox(height: 6),
    pw.Text(
      'Rating (§8a): ${data?.rating?.label ?? '—'}',
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
  ];
}

/// Generates Form 5c — Evaluation Guide — one panelist's completed scoring
/// sheet, as a PDF. `compress: false` keeps the content streams
/// text-greppable; see `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm5cPdf(Form5cData data) async {
  final doc = pw.Document(compress: false);

  doc.addPage(
    // MultiPage, not Page: eleven criteria with prompts and comments will
    // not fit one sheet. See form1_pdf.dart for why Page silently clips.
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(data: data),
    ),
  );

  return doc.save();
}

/// A blank Form 5c: the same chrome, the same eleven criteria, the same
/// section headings and summary rows as [buildForm5cPdf] — nothing filled
/// in, because there is no [Form5cData] to fill it with. Unlike Form 8, an
/// unfilled rubric needs no template marking: a page of ruled lines and
/// blank score boxes is obviously unfilled on its face, and marking it
/// would only clutter a form meant to be printed and written on.
Future<Uint8List> buildForm5cBlank() async {
  final doc = pw.Document(compress: false);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(),
    ),
  );

  return doc.save();
}
