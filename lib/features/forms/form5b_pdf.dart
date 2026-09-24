import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form5b_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Form 5b's text, block by block, for an editable copy: each field's label
/// and its value.
final FormTemplate form5bTemplate = FormTemplate(
  formId: 'form5b',
  title: 'Form 5b — Presenter and Evaluator Profile',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-37-06/24-04',
      formTitle: 'Res. Form 5b. Presenter and Evaluator Profile',
    ),
    ...fieldBlocks('presenter', 'Name of Presenter'),
    ...fieldBlocks('degree', 'Degree and Field of Specialization'),
    ...fieldBlocks('presentedDate', 'Date of Presentation'),
    ...fieldBlocks('presentedTime', 'Time of Presentation'),
    ...fieldBlocks('venue', 'Venue'),
    ...fieldBlocks('studyTitle', 'Title of the Study'),
    ...fieldBlocks('evaluator', 'Evaluator'),
    ...fieldBlocks('rank', 'Academic Rank'),
    ...fieldBlocks('specialization', 'Field of Specialization'),
  ],
  layout: (t) => [_page(t)],
);

/// The whole printed page, shared by a real profile, the blank template and
/// an editable copy. A field prints the app's value when there is one,
/// otherwise its typed text, otherwise a ruled blank.
pw.Widget _page(FormText t, {Form5bData? data}) {
  final presentedOn = data?.presentedOn;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 16),
      formField(
        t.of('presenter.label'),
        valueOr(
          data == null || data.presenterNames.isEmpty
              ? null
              : data.presenterNames.join(', '),
          t,
          'presenter',
        ),
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
      formField(
          t.of('studyTitle.label'), valueOr(data?.title, t, 'studyTitle')),
      pw.SizedBox(height: 12),
      formField(t.of('evaluator.label'),
          valueOr(data?.evaluatorName, t, 'evaluator')),
      formField(t.of('rank.label'), valueOr(null, t, 'rank')),
      formField(t.of('specialization.label'),
          valueOr(data?.evaluatorField, t, 'specialization')),
    ],
  );
}

/// Generates Form 5b — Presenter and Evaluator Profile — as a PDF.
/// `compress: false` keeps the content streams text-greppable.
Future<Uint8List> buildForm5bPdf(Form5bData data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5bTemplate), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 5b: the same chrome and fields as [buildForm5bPdf], every
/// one of them a ruled line.
Future<Uint8List> buildForm5bBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5bTemplate)),
    ),
  );
  return doc.save();
}
