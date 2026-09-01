import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Generates Form 8 — Certification of Submission of Bound Copies — as a
/// PDF. `compress: false` keeps the content streams text-greppable; see
/// `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm8Pdf(Form8Data data) async {
  final doc = pw.Document(compress: false);
  final issuedOn = data.issuedOn;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => pw.Column(
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
          pw.SizedBox(height: 16),
          pw.Text(
            'This is to certify that ${panelSentence(data.studentNames)} has '
            'submitted bound copies of his/her undergraduate thesis entitled '
            '"${data.title}".',
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
      ),
    ),
  );

  return doc.save();
}
