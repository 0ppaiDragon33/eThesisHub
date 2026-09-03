import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form7_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// The seven roles the printed review table always lists, in the order
/// the form prints them. Never resolved from data — see `Form7Data`'s
/// doc comment for why: two of these roles are not modelled anywhere in
/// this app, so no row is prefilled and every row stays blank alike.
const _panelRoles = [
  'Dean',
  'Research Coordinator',
  'Thesis Adviser',
  'Member',
  'Member',
  'Grammarian',
  'Statistician',
];

pw.Widget _tableCell(String text, {bool header = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
  child: pw.Text(
    text,
    style: header
        ? pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)
        : const pw.TextStyle(fontSize: 9),
  ),
);

/// The whole printed page, shared by a real certificate and the blank
/// template. `data == null` is the template case.
///
/// Only the two identifying lines above the review table differ between
/// the two — the presenter and the title, each ruled blank when there is
/// no [Form7Data] at all. The table below is identical either way.
pw.Widget _page({Form7Data? data}) {
  final presenters = data == null || data.presenterNames.isEmpty
      ? null
      : panelSentence(data.presenterNames);
  final title = data?.title.isNotEmpty == true ? data!.title : null;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(
        rdCode: 'RD-38-06/24-04',
        formTitle: 'Form 7. Certificate of Review',
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
      pw.Center(
        child: pw.Text(
          'CERTIFICATION OF REVIEW',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Text(
        'This is to certify that the undersigned Thesis Panel Members '
        'have reviewed and approved for reproduction of the manuscript of',
        style: _bodyStyle,
        textAlign: pw.TextAlign.justify,
      ),
      pw.SizedBox(height: 4),
      presenters != null
          ? pw.Text(presenters, style: _bodyStyle)
          : ruledLine(width: 300),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '(Name of Student)',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Text('Entitled', style: _bodyStyle),
      pw.SizedBox(height: 4),
      title != null
          ? pw.Text('"$title"', style: _bodyStyle)
          : ruledLine(width: 460),
      pw.SizedBox(height: 18),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.6),
          1: pw.FlexColumnWidth(2.4),
          2: pw.FlexColumnWidth(2.0),
        },
        children: [
          pw.TableRow(
            children: [
              _tableCell('Panel Member', header: true),
              _tableCell('Approved', header: true),
              _tableCell('Remarks', header: true),
            ],
          ),
          for (var i = 0; i < _panelRoles.length; i++)
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${i + 1}.',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      ruledLine(width: 140, height: 10),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _panelRoles[i],
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: ruledLine(width: 100, height: 10),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: ruledLine(width: 90, height: 10),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Generates Form 7 — Certificate of Review — as a PDF. `compress: false`
/// keeps the content streams text-greppable.
Future<Uint8List> buildForm7Pdf(Form7Data data) async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => [_page(data: data)],
    ),
  );
  return doc.save();
}

/// A blank Form 7: the same chrome, certification sentence and review
/// table as [buildForm7Pdf], with the presenter and title lines ruled.
Future<Uint8List> buildForm7Blank() async {
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => [_page()],
    ),
  );
  return doc.save();
}
