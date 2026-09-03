import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form5a_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// The whole printed page, shared by a real letter and the blank
/// template. `data == null` is the template case. See `form3_pdf.dart`'s
/// `_page` for the sibling of this — same shape, this letter's own body
/// and signer.
pw.Widget _page({Form5aData? data}) {
  final title = data?.title.isNotEmpty == true ? data!.title : null;
  final scheduledAt = data?.scheduledAt;
  final venue = data?.venue.isNotEmpty == true ? data!.venue : null;
  final college = data?.college ?? '';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(
        rdCode: 'RD-36-06/24-04',
        formTitle: 'Form 5a. Request for Final Oral Defense',
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
      pw.Text(
        college.isEmpty ? 'College of ${'_' * 20}' : 'College of $college',
        style: _bodyStyle,
      ),
      pw.Text(
        'Iloilo State University of Fisheries Science and Technology',
        style: _bodyStyle,
      ),
      pw.Text('Barotac Nuevo, Iloilo', style: _bodyStyle),
      pw.SizedBox(height: 12),
      pw.Text('Sir/Madam:', style: _bodyStyle),
      pw.SizedBox(height: 10),
      pw.Text(
        'I have the honor to request for the final oral defense of my '
        'undergraduate thesis entitled',
        style: _bodyStyle,
      ),
      pw.SizedBox(height: 4),
      title != null
          ? pw.Text('"$title".', style: _bodyStyle)
          : ruledLine(width: 400),
      pw.SizedBox(height: 8),
      pw.Text('The final oral defense will be conducted on', style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          scheduledAt == null
              ? ruledLine(width: 100)
              : pw.Text(
                  '${scheduledAt.day} ${monthName(scheduledAt.month)} '
                  '${scheduledAt.year}',
                  style: _bodyStyle,
                ),
          pw.Text(' in ', style: _bodyStyle),
          pw.Expanded(
            child: venue != null
                ? pw.Text(venue, style: _bodyStyle)
                : ruledLine(),
          ),
          pw.Text(' at ', style: _bodyStyle),
          scheduledAt == null
              ? ruledLine(width: 80)
              : pw.Text(
                  '${scheduledAt.hour.toString().padLeft(2, '0')}:'
                  '${scheduledAt.minute.toString().padLeft(2, '0')}',
                  style: _bodyStyle,
                ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        '(Place)                                                  (Time)',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 12),
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
      pw.Text('Noted:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      signableLine('', 'Thesis Adviser'),
      pw.Text(
        'Recommending Approval:',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine('', 'College Research Coordinator'),
      pw.Text('Approved:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      signableLine('', 'Dean, ${college.isEmpty ? '________' : college}'),
    ],
  );
}

/// Generates Form 5a — Request for Final Oral Defense — as a PDF.
Future<Uint8List> buildForm5aPdf(Form5aData data) async {
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

/// A blank Form 5a: the same chrome and letter body as [buildForm5aPdf],
/// with every variable clause a ruled line.
Future<Uint8List> buildForm5aBlank() async {
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
