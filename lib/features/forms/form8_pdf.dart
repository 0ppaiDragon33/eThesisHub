import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Form 8's text, block by block, for an editable copy.
///
/// The two identifying clauses sit mid-sentence inside justified prose, so
/// they are plain underscores rather than ruled lines: a rule widget cannot
/// be dropped into the middle of a `pw.Text`. As editable blocks they are
/// ordinary text whose default is those underscores.
final FormTemplate form8Template = FormTemplate(
  formId: 'form8',
  title: 'Form 8 — Certification of Submission of Bound Copies',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-39-06/24-04',
      formTitle: 'Form 8. Certification of Submission of Bound Copies',
    ),
    const FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
    const FormBlock(
      id: 'dateLabel',
      label: 'Label under the date',
      defaultText: 'Date',
    ),
    const FormBlock(
      id: 'heading',
      label: 'Heading',
      defaultText: 'CERTIFICATION',
    ),
    const FormBlock(
      id: 'certifyLead',
      label: 'Before the names',
      defaultText: 'This is to certify that',
    ),
    FormBlock(id: 'students', label: 'Student names', defaultText: '_' * 31),
    const FormBlock(
      id: 'certifyMiddle',
      label: 'Between the names and the title',
      multiline: true,
      defaultText:
          'has submitted bound copies of his/her undergraduate '
          'thesis entitled',
    ),
    FormBlock(
      id: 'thesisTitle',
      label: 'Thesis title',
      multiline: true,
      defaultText: '_' * 55,
    ),
    const FormBlock(
      id: 'signer.role',
      label: 'Signer: title',
      defaultText: 'Research Coordinator/Chair',
    ),
  ],
  layout: (t) => [_page(t)],
);

/// The whole printed page, shared by a real certificate, the blank template
/// and an editable copy. With app data, the date, the names and the title
/// print from it; without, from the blocks.
///
/// No "blank template" marking and no watermark: both were built and then
/// taken out. The blank is a sheet somebody prints and completes by hand;
/// once completed and signed it IS an issued certification. `Form8Unissuable`
/// guards the case that matters, a certificate generated from incomplete
/// real data.
pw.Widget _page(FormText t, {Form8Data? data}) {
  final issuedOn = data?.issuedOn;
  final studentsText = data == null
      ? t.of('students')
      : panelSentence(data.studentNames);
  final titleText = data == null ? t.of('thesisTitle') : data.title;

  final pw.Widget date;
  if (issuedOn != null) {
    date = pw.Text(
      '${issuedOn.day} ${monthName(issuedOn.month)} ${issuedOn.year}',
      textAlign: pw.TextAlign.center,
    );
  } else if (t.isBlank('date')) {
    date = pw.Container(
      height: 14,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
      ),
    );
  } else {
    date = pw.Text(t.of('date'), textAlign: pw.TextAlign.center);
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(width: 160, child: date),
            pw.SizedBox(height: 2),
            pw.Text(t.of('dateLabel'), style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
      pw.SizedBox(height: 20),
      pw.Center(
        child: pw.Text(
          t.of('heading'),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 16),
      pw.Text(
        '${t.of('certifyLead')} $studentsText ${t.of('certifyMiddle')} '
        '"$titleText".',
        textAlign: pw.TextAlign.justify,
        style: const pw.TextStyle(fontSize: 11),
      ),
      pw.SizedBox(height: 60),
      pw.Center(
        child: pw.Column(
          children: [
            pw.Container(width: 220, height: 1, color: PdfColors.grey700),
            pw.SizedBox(height: 3),
            pw.Text(
              t.of('signer.role'),
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Generates Form 8 — Certification of Submission of Bound Copies — as a
/// PDF. `compress: false` keeps the content streams text-greppable; see
/// `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm8Pdf(Form8Data data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form8Template), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 8: the same chrome, date rule, prose and signature line as
/// [buildForm8Pdf], with the two identifying clauses as underscores. It is
/// meant to be printed and completed by hand.
Future<Uint8List> buildForm8Blank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form8Template)),
    ),
  );
  return doc.save();
}
