import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form3_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// The whole printed page, shared by a real letter and the blank
/// template. `data == null` is the template case.
///
/// The letter's four variable clauses (presenter, panel, title, and the
/// date/place/time trio) are `ruledLine`s when blank, plain text when
/// filled — nothing else on the page differs, so a filled letter and a
/// blank one are provably the same layout.
pw.Widget _page({Form3Data? data}) {
  final presenters = data == null || data.presenterNames.isEmpty
      ? null
      : panelSentence(data.presenterNames);
  final panel = data == null || data.panelNames.isEmpty
      ? null
      : data.panelNames;
  final title = data?.title.isNotEmpty == true ? data!.title : null;
  final scheduledAt = data?.scheduledAt;
  final venue = data?.venue.isNotEmpty == true ? data!.venue : null;
  final college = data?.college ?? '';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(
        rdCode: 'RD-33-06/24-04',
        formTitle:
            'Form 3. Request to Convene the Thesis Panel Members for '
            'Pre-Oral Defense',
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
        'I would like to request the Undergraduate Thesis Panel Members '
        'consisting of:',
        style: _bodyStyle,
      ),
      pw.SizedBox(height: 8),
      if (panel != null)
        for (final name in panel)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(name, style: _bodyStyle),
          )
      else
        for (var i = 0; i < 3; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: ruledLine(width: 260),
          ),
      pw.SizedBox(height: 8),
      pw.Text(
        'To convene and deliberate on the proposal of '
        '${presenters ?? ''}',
        style: _bodyStyle,
      ),
      if (presenters == null) ruledLine(width: 220),
      pw.SizedBox(height: 4),
      pw.Text('entitled', style: _bodyStyle),
      if (title != null)
        pw.Text(title, style: _bodyStyle)
      else
        ruledLine(width: 400),
      pw.SizedBox(height: 8),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('on ', style: _bodyStyle),
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
        ],
      ),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('at ', style: _bodyStyle),
          scheduledAt == null
              ? ruledLine(width: 100)
              : pw.Text(
                  '${scheduledAt.hour.toString().padLeft(2, '0')}:'
                  '${scheduledAt.minute.toString().padLeft(2, '0')}',
                  style: _bodyStyle,
                ),
          pw.Expanded(child: pw.SizedBox()),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        '(Place)                                             (Time)',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 12),
      pw.Text(
        'Your approval on this request is highly appreciated.',
        style: _bodyStyle,
      ),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Very truly yours,', style: _bodyStyle),
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: signableLine('', 'Thesis Adviser'),
      ),
      pw.SizedBox(height: 8),
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

/// Generates Form 3 — Request to Convene the Thesis Panel Members for
/// Pre-Oral Defense — as a PDF. `compress: false` keeps the content
/// streams text-greppable; see `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm3Pdf(Form3Data data) async {
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

/// A blank Form 3: the same chrome and letter body as [buildForm3Pdf],
/// with every variable clause a ruled line — meant to be printed and
/// completed by hand, the way this letter is actually used before a
/// defence exists in the app at all.
Future<Uint8List> buildForm3Blank() async {
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
