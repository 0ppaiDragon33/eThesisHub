import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 4b — Change of Undergraduate Thesis Title. Blank template ONLY,
/// for the same reason as Form 4a: the app has no "change the approved
/// title" workflow. Title changes go through M1b's multi-round title
/// defence instead, which is a different mechanism from a simple
/// approved-title-to-new-title-with-reasons letter. See `form4a_pdf.dart`
/// for the fuller reasoning — it applies here unchanged.
Future<Uint8List> buildForm4bBlank() async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          formChrome(
            rdCode: 'RD-35-06/24-04',
            formTitle: 'Form 4b. Change of Undergraduate Thesis Title',
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: ruledLine(width: 140),
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Date', style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.SizedBox(height: 16),
          pw.Text('The Dean', style: _bodyStyle),
          pw.Text('College of ${'_' * 20}', style: _bodyStyle),
          pw.Text(
            'Iloilo State University of Fisheries Science and Technology',
            style: _bodyStyle,
          ),
          pw.Text('Barotac Nuevo, Iloilo', style: _bodyStyle),
          pw.SizedBox(height: 12),
          pw.Text('Sir/Madam:', style: _bodyStyle),
          pw.SizedBox(height: 10),
          pw.Text(
            'I would like to request for the change of my undergraduate '
            'Thesis Title',
            style: _bodyStyle,
          ),
          pw.SizedBox(height: 6),
          ruledLine(width: 460),
          pw.SizedBox(height: 4),
          pw.Text('to', style: _bodyStyle),
          pw.SizedBox(height: 6),
          ruledLine(width: 460),
          pw.SizedBox(height: 10),
          pw.Text('for the following reasons:', style: _bodyStyle),
          pw.SizedBox(height: 6),
          for (var i = 0; i < 3; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: ruledLine(width: 460),
            ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Your approval on this matter is highly appreciated.',
            style: _bodyStyle,
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Respectfully yours,', style: _bodyStyle),
          ),
          pw.SizedBox(height: 4),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: signableLine('', 'Student'),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Noted:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          signableLine('', 'Thesis Adviser'),
          pw.Text(
            'Recommending Approval:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          signableLine('', 'College Research Coordinator'),
          pw.Text(
            'Approved:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          signableLine('', 'Dean, ________'),
        ],
      ),
    ),
  );
  return doc.save();
}
