import 'dart:typed_data';
import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Placeholder text for the blank template's two variable clauses. Plain
/// underscores, not a ruled `pw.Container`, because both sit mid-sentence
/// inside justified prose — a rule widget cannot be dropped into the
/// middle of a `pw.Text` the way [Form5cData]'s field rows can.
const _blankName = '_______________________________';
const _blankTitle =
    '_______________________________________________________';

/// The whole printed page, shared by a real certificate and the blank
/// template. `data == null` is the template case.
///
/// §6 (`Form8Unissuable`) exists because a blank-looking certificate reads
/// as official. A template built with no [Form8Data] at all is exactly
/// that risk, so unlike Form 5c's rubric (obviously unfilled on its face),
/// this page adds a diagonal watermark and a line under CERTIFICATION
/// saying plainly that it is a template — the two must never contradict
/// each other, and the marking is what keeps them from doing so.
pw.Widget _page({Form8Data? data}) {
  final isBlank = data == null;
  final issuedOn = data?.issuedOn;
  final studentsText = data == null ? _blankName : panelSentence(data.studentNames);
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
      if (isBlank) ...[
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'BLANK TEMPLATE — not an issued certification.',
            style: pw.TextStyle(
              fontSize: 9,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.red700,
            ),
          ),
        ),
      ],
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
            pw.Container(
              width: 220,
              height: 1,
              color: PdfColors.grey700,
            ),
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

  if (!isBlank) return content;

  // The diagonal watermark. Positioned.fill gives pw.Watermark the bounded
  // box it needs (it expands to fill its parent), sized to the page's
  // content area rather than the untamed page itself.
  return pw.Stack(
    children: [
      content,
      pw.Positioned.fill(
        child: pw.Watermark.text(
          'TEMPLATE',
          angle: math.pi / 6,
          style: pw.TextStyle(
            color: PdfColors.grey300,
            fontWeight: pw.FontWeight.bold,
            fontSize: 64,
          ),
        ),
      ),
    ],
  );
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

/// A blank Form 8: the same chrome, date rule and signature line as
/// [buildForm8Pdf], with the two identifying clauses replaced by
/// underscores and a diagonal "TEMPLATE" watermark plus a line under
/// CERTIFICATION marking it as unissued (see [_page]'s doc comment for
/// why Form 8, unlike Form 5c, needs this).
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
