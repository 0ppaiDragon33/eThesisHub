import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _valueStyle = pw.TextStyle(fontSize: 10.5);
const _promptStyle = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600);
const _sectionHeaderStyle = pw.TextStyle(
  fontSize: 11,
  fontWeight: pw.FontWeight.bold,
  color: formAccent,
);

List<EvaluationCriterion> _criteriaIn(EvaluationSection section) =>
    evaluationCriteria.where((c) => c.section == section).toList();

/// A criterion's editable blocks: its name, its prompt (Section A only, and
/// only where the rubric has one), its score, and its comment (Section A
/// only). The weight is not a block: it defines the scoring.
List<FormBlock> _criterionBlocks(EvaluationCriterion c) => [
  FormBlock(
    id: 'criterion.${c.key}.label',
    label: '${c.label}: criterion',
    defaultText: c.label,
  ),
  if (c.takesComment && c.prompt.isNotEmpty)
    FormBlock(
      id: 'criterion.${c.key}.prompt',
      label: '${c.label}: prompt',
      defaultText: c.prompt,
      multiline: true,
    ),
  FormBlock(
    id: 'criterion.${c.key}.score',
    label: '${c.label}: score (out of ${c.weight})',
    kind: BlockKind.blank,
  ),
  if (c.takesComment)
    FormBlock(
      id: 'criterion.${c.key}.comment',
      label: '${c.label}: comment',
      kind: BlockKind.blank,
      multiline: true,
    ),
];

/// Form 5c's text, block by block, for an editable copy.
final FormTemplate form5cTemplate = FormTemplate(
  formId: 'form5c',
  title: 'Form 5c — Evaluation Guide',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-37-06/24-04',
      formTitle: 'Form 5c. Evaluation Guide',
    ),
    const FormBlock(
      id: 'guideHeading',
      label: 'Heading',
      defaultText: 'EVALUATION GUIDE',
    ),
    const FormBlock(
      id: 'guideSubheading',
      label: 'Subheading',
      defaultText: 'FOR REPORTS ON RESEARCHES AND TECHNICAL PAPERS',
    ),
    ...fieldBlocks('presenter', 'Name of Presenter'),
    ...fieldBlocks('degree', 'Degree and Field of Specialization'),
    ...fieldBlocks('presentedDate', 'Date of Presentation'),
    ...fieldBlocks('presentedTime', 'Time of Presentation'),
    ...fieldBlocks('venue', 'Venue'),
    ...fieldBlocks('studyTitle', 'Title of the Study'),
    ...fieldBlocks('defence', 'Defence'),
    ...fieldBlocks('evaluator', 'Evaluator'),
    ...fieldBlocks('rank', 'Academic Rank'),
    ...fieldBlocks('specialization', 'Field of Specialization'),
    // The "(50%)" in these headings is display text only, editable like any
    // other block. Scoring reads the fixed criterion weights below, not
    // this heading text, so editing it does not change how the form scores.
    const FormBlock(
      id: 'sectionA',
      label: 'Section A heading',
      defaultText: 'A. CONTENT (50%)',
    ),
    for (final c in _criteriaIn(EvaluationSection.content))
      ..._criterionBlocks(c),
    const FormBlock(
      id: 'sectionB',
      label: 'Section B heading',
      defaultText: 'B. PRESENTATION AND DEFENSE (50%)',
    ),
    for (final c in _criteriaIn(EvaluationSection.presentation))
      ..._criterionBlocks(c),
    const FormBlock(
      id: 'summaryHeading',
      label: 'Summary heading',
      defaultText: 'SUMMARY',
    ),
    ...fieldBlocks('summaryA', 'A. CONTENT'),
    ...fieldBlocks('summaryB', 'B. PRESENTATION AND DEFENSE'),
    ...fieldBlocks('average', 'Average Rating'),
    ...fieldBlocks('finalGrade', 'Final Grade'),
    const FormBlock(
      id: 'rating.label',
      label: 'Rating (label)',
      defaultText: 'Rating (§8a):',
    ),
    const FormBlock(id: 'rating', label: 'Rating', defaultText: '—'),
  ],
  layout: (t) => _page(t),
);

/// One rubric row: name + weight, the prompt (Section A only), the score out
/// of the weight, and a comment line where one was written (Section A only).
///
/// With app data ([scores] non-null) a missing score rules a blank, never a
/// 0: "0 / 25" would read as a genuine zero. Without app data (the blank
/// template, an editable copy) the score and comment come from the blocks.
pw.Widget _criterionRow(
  FormText t,
  EvaluationCriterion c, {
  Map<String, int>? scores,
  Map<String, String>? comments,
}) {
  final score = scores != null
      ? scores[c.key]?.toString()
      : valueOr(null, t, 'criterion.${c.key}.score');
  final comment = !c.takesComment
      ? null
      : comments != null
      ? comments[c.key]
      : valueOr(null, t, 'criterion.${c.key}.comment');
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
                '${t.of('criterion.${c.key}.label')} (${c.weight}%)',
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
                  formRule(width: 26),
                  pw.SizedBox(width: 4),
                  pw.Text('/ ${c.weight}', style: _valueStyle),
                ],
              )
            else
              pw.Text('$score / ${c.weight}', style: _valueStyle),
          ],
        ),
        if (c.takesComment && c.prompt.isNotEmpty)
          pw.Text(t.of('criterion.${c.key}.prompt'), style: _promptStyle),
        if (comment != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text('Comment: $comment', style: _promptStyle),
          ),
      ],
    ),
  );
}

/// A "label ... total" summary row. A null [value] rules a blank rather than
/// printing a total of 0.
pw.Widget _summaryRow(String label, String? value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: _valueStyle),
        value == null
            ? formRule(width: 40)
            : pw.Text(value, style: _valueStyle),
      ],
    ),
  );
}

/// The whole printed sheet, shared by a real evaluation, the blank template
/// and an editable copy. `data == null` is the template and copy case: every
/// field, score and total comes from its block (typed text, or a ruled
/// blank). With app data, the data prints exactly as it always has.
List<pw.Widget> _page(FormText t, {Form5cData? data}) {
  final presentedOn = data?.presentedOn;
  final scores = data?.scores;
  final comments = data?.comments;

  return [
    formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
    pw.SizedBox(height: 10),
    pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            t.of('guideHeading'),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            t.of('guideSubheading'),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    ),
    pw.SizedBox(height: 12),

    formField(
      t.of('presenter.label'),
      valueOr(data?.presenterNames.join(', '), t, 'presenter'),
    ),
    formField(t.of('degree.label'), valueOr(null, t, 'degree')),
    formField(
      t.of('presentedDate.label'),
      valueOr(
        presentedOn == null
            ? null
            : '${presentedOn.day} ${monthName(presentedOn.month)} '
                  '${presentedOn.year}',
        t,
        'presentedDate',
      ),
    ),
    formField(
      t.of('presentedTime.label'),
      valueOr(
        presentedOn == null
            ? null
            : '${presentedOn.hour.toString().padLeft(2, '0')}:'
                  '${presentedOn.minute.toString().padLeft(2, '0')}',
        t,
        'presentedTime',
      ),
    ),
    formField(t.of('venue.label'), valueOr(data?.venue, t, 'venue')),
    formField(t.of('studyTitle.label'), valueOr(data?.title, t, 'studyTitle')),
    formField(
      t.of('defence.label'),
      valueOr(data?.defenceType.label, t, 'defence'),
    ),
    formField(
      t.of('evaluator.label'),
      valueOr(data?.evaluatorName, t, 'evaluator'),
    ),
    formField(t.of('rank.label'), valueOr(null, t, 'rank')),
    formField(
      t.of('specialization.label'),
      valueOr(data?.evaluatorField, t, 'specialization'),
    ),

    pw.SizedBox(height: 14),
    pw.Container(height: 1, color: PdfColors.grey400),
    pw.SizedBox(height: 8),

    pw.Text(t.of('sectionA'), style: _sectionHeaderStyle),
    pw.SizedBox(height: 4),
    for (final c in _criteriaIn(EvaluationSection.content))
      _criterionRow(t, c, scores: scores, comments: comments),

    pw.SizedBox(height: 8),
    pw.Text(t.of('sectionB'), style: _sectionHeaderStyle),
    pw.SizedBox(height: 4),
    for (final c in _criteriaIn(EvaluationSection.presentation))
      _criterionRow(t, c, scores: scores, comments: comments),

    pw.SizedBox(height: 14),
    pw.Container(height: 1, color: PdfColors.grey400),
    pw.SizedBox(height: 8),
    pw.Text(
      t.of('summaryHeading'),
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 6),
    _summaryRow(
      t.of('summaryA.label'),
      valueOr(data?.sectionATotal.toString(), t, 'summaryA'),
    ),
    _summaryRow(
      t.of('summaryB.label'),
      valueOr(data?.sectionBTotal.toString(), t, 'summaryB'),
    ),
    // The app does not compute an average (D62); a labelled blank says so.
    formField(t.of('average.label'), valueOr(null, t, 'average')),
    _summaryRow(
      t.of('finalGrade.label'),
      valueOr(data?.finalGrade.toString(), t, 'finalGrade'),
    ),
    pw.SizedBox(height: 6),
    pw.Text(
      '${t.of('rating.label')} ${data?.rating?.label ?? t.of('rating')}',
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
  ];
}

/// Generates Form 5c — Evaluation Guide — one panelist's completed scoring
/// sheet, as a PDF. MultiPage: eleven criteria with prompts and comments do
/// not fit one sheet (see form1_pdf.dart for why Page silently clips).
Future<Uint8List> buildForm5cPdf(Form5cData data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5cTemplate), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 5c: the same chrome, criteria, headings and summary rows as
/// [buildForm5cPdf], nothing filled in. An unfilled rubric needs no template
/// marking; a page of ruled lines is obviously unfilled.
Future<Uint8List> buildForm5cBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5cTemplate)),
    ),
  );
  return doc.save();
}
