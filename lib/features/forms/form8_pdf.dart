import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Placeholder text for the blank template's two variable clauses. Plain
/// underscores, not a ruled `pw.Container`, because both sit mid-sentence
/// inside justified prose — a rule widget cannot be dropped into the
/// middle of a `pw.Text` the way [Form5cData]'s field rows can.
const _blankName = '_______________________________';
const _blankTitle = '_______________________________________________________';

/// The whole printed page, shared by a real certificate and the blank
/// template. `data == null` is the template case.
///
/// The two render IDENTICALLY apart from the two clauses — no watermark,
/// no "this is a template" banner. See the note at the CERTIFICATION
/// heading for why those were built and then taken out.
pw.Widget _page({Form8Data? data}) {
  final issuedOn = data?.issuedOn;
  final studentsText = data == null
      ? _blankName
      : panelSentence(data.studentNames);
  final titleText = data == null ? _blankTitle : data.title;

  final content = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(
        rdCode: 'RD-39-06/24-04',
        formTitle: 'Form 8. Certification of Submission of Bound Copies',
      ),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 160,
              child: issuedOn == null
                  ? pw.Container(
                      height: 14,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey400),
                        ),
                      ),
                    )
                  : pw.Text(
                      '${issuedOn.day} ${monthName(issuedOn.month)} '
                      '${issuedOn.year}',
                      textAlign: pw.TextAlign.center,
                    ),
            ),
            pw.SizedBox(height: 2),
            pw.Text('Date', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
      pw.SizedBox(height: 20),
      pw.Center(
        child: pw.Text(
          'CERTIFICATION',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
      // NO "blank template" marking, and no watermark below — both were
      // built and then removed once the printed page was looked at.
      //
      // The reasoning that put them there treated the blank as a FILE that
      // might be mistaken for a real certificate. It is not: it is a sheet
      // somebody prints and completes by hand, which is how every form in
      // these Guidelines is actually used. A watermark means writing over
      // grey letterforms, and the marking becomes untrue the moment the
      // form is used as intended — once completed and signed, the paper IS
      // an issued certification while still saying it is not.
      //
      // `Form8Unissuable` still guards the case that actually matters: a
      // certificate generated from real-but-incomplete data, which is the
      // document that could be passed off as issued. A blank with ruled
      // lines cannot be — the lines are empty.
      pw.SizedBox(height: 16),
      pw.Text(
        'This is to certify that $studentsText has '
        'submitted bound copies of his/her undergraduate thesis entitled '
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
              'Research Coordinator/Chair',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
    ],
  );

  return content;
}

/// Generates Form 8 — Certification of Submission of Bound Copies — as a
/// PDF. `compress: false` keeps the content streams text-greppable; see
/// `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm8Pdf(Form8Data data) async {
  final doc = pw.Document(compress: false);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(data: data),
    ),
  );

  return doc.save();
}

/// A blank Form 8: the same chrome, date rule, prose and signature line as
/// [buildForm8Pdf], with the two identifying clauses replaced by ruled
/// underscores. Nothing else differs — it is meant to be printed and
/// completed by hand, so it carries no marking to write around.
Future<Uint8List> buildForm8Blank() async {
  final doc = pw.Document(compress: false);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(),
    ),
  );

  return doc.save();
}
