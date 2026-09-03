import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 4a — Change of Undergraduate Thesis Adviser. Blank template
/// ONLY, deliberately: unlike Forms 3/5a/5b, the app tracks no adviser
/// reassignment workflow at all. `Thesis.adviserUid` is set once at
/// nomination approval, with no reassignment path — there is no "former
/// adviser", "nominated adviser" or reason-for-change anywhere in the
/// data model. Filling this in would mean designing and building a
/// change-request workflow the Guidelines describe and the app has never
/// had, which is new scope, not a rendering task. So this generates the
/// same blank every time, printed and completed by hand — exactly how
/// this letter is used today.
Future<Uint8List> buildForm4aBlank() async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          formChrome(
            rdCode: 'RD-34-06/24-04',
            formTitle: 'Form 4a. Change of Undergraduate Thesis Adviser',
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
            'Thesis Adviser',
            style: _bodyStyle,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              ruledLine(width: 260),
              pw.SizedBox(width: 6),
              pw.Text('to', style: _bodyStyle),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '(Nominated Adviser)',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 4),
          ruledLine(width: 260),
          pw.Text(
            '(Former Adviser)',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
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
            'Conforme:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          signableLine('', 'Nominated Adviser'),
          signableLine('', 'Former Adviser'),
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
