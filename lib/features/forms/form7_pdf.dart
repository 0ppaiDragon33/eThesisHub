import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form7_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);
const _cellStyle = pw.TextStyle(fontSize: 9);

/// The seven roles the printed review table lists, in order. Each is the
/// default of its row's role block. Never resolved from data: two of these
/// roles are not modelled anywhere in this app (see `Form7Data`).
const _panelRoles = [
  'Dean',
  'Research Coordinator',
  'Thesis Adviser',
  'Member',
  'Member',
  'Grammarian',
  'Statistician',
];

/// Form 7's text, block by block, for an editable copy.
final FormTemplate form7Template = FormTemplate(
  formId: 'form7',
  title: 'Form 7 — Certificate of Review',
  blocks: [
    ...formHeadBlocks(
      rdCode: 'RD-38-06/24-04',
      formTitle: 'Form 7. Certificate of Review',
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
      defaultText: 'CERTIFICATION OF REVIEW',
    ),
    const FormBlock(
      id: 'certify',
      label: 'Certification',
      multiline: true,
      defaultText:
          'This is to certify that the undersigned Thesis Panel '
          'Members have reviewed and approved for reproduction of the '
          'manuscript of',
    ),
    const FormBlock(
      id: 'presenters',
      label: 'Name of student',
      kind: BlockKind.blank,
    ),
    const FormBlock(
      id: 'presentersLabel',
      label: 'Label under the name',
      defaultText: '(Name of Student)',
    ),
    const FormBlock(
      id: 'entitled',
      label: 'Before the title',
      defaultText: 'Entitled',
    ),
    const FormBlock(
      id: 'title',
      label: 'Thesis title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(
      id: 'table.member',
      label: 'Column: panel member',
      defaultText: 'Panel Member',
    ),
    const FormBlock(
      id: 'table.approved',
      label: 'Column: approved',
      defaultText: 'Approved',
    ),
    const FormBlock(
      id: 'table.remarks',
      label: 'Column: remarks',
      defaultText: 'Remarks',
    ),
    for (var i = 1; i <= _panelRoles.length; i++) ...[
      FormBlock(
        id: 'panel.$i.name',
        label: 'Row $i: name',
        kind: BlockKind.blank,
      ),
      FormBlock(
        id: 'panel.$i.role',
        label: 'Row $i: role',
        defaultText: _panelRoles[i - 1],
      ),
      FormBlock(
        id: 'panel.$i.approved',
        label: 'Row $i: approved',
        kind: BlockKind.blank,
      ),
      FormBlock(
        id: 'panel.$i.remarks',
        label: 'Row $i: remarks',
        kind: BlockKind.blank,
      ),
    ],
  ],
  layout: (t) => [_page(t)],
);

pw.Widget _tableCell(String text, {bool header = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
  child: pw.Text(
    text,
    style: header
        ? pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)
        : _cellStyle,
  ),
);

/// The whole printed page, shared by a real certificate, the blank template
/// and an editable copy. With app data, the presenter and the title print
/// from it; everything else, and both of those without data, comes from the
/// blocks.
pw.Widget _page(FormText t, {Form7Data? data}) {
  final presenters = data == null || data.presenterNames.isEmpty
      ? null
      : panelSentence(data.presenterNames);
  final title = data?.title.isNotEmpty == true ? data!.title : null;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: blankOr(t, 'date', width: 140, style: _bodyStyle),
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          t.of('dateLabel'),
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      pw.SizedBox(height: 16),
      pw.Center(
        child: pw.Text(
          t.of('heading'),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Text(
        t.of('certify'),
        style: _bodyStyle,
        textAlign: pw.TextAlign.justify,
      ),
      pw.SizedBox(height: 4),
      dataOr(presenters, t, 'presenters', width: 300, style: _bodyStyle),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          t.of('presentersLabel'),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Text(t.of('entitled'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      dataOr(
        title == null ? null : '"$title"',
        t,
        'title',
        width: 460,
        style: _bodyStyle,
      ),
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
              _tableCell(t.of('table.member'), header: true),
              _tableCell(t.of('table.approved'), header: true),
              _tableCell(t.of('table.remarks'), header: true),
            ],
          ),
          for (var i = 1; i <= _panelRoles.length; i++)
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
                      pw.Text('$i.', style: _cellStyle),
                      blankOr(
                        t,
                        'panel.$i.name',
                        width: 140,
                        height: 10,
                        style: _cellStyle,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        t.of('panel.$i.role'),
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
                  child: blankOr(
                    t,
                    'panel.$i.approved',
                    width: 100,
                    height: 10,
                    style: _cellStyle,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: blankOr(
                    t,
                    'panel.$i.remarks',
                    width: 90,
                    height: 10,
                    style: _cellStyle,
                  ),
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
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => [_page(FormText(form7Template), data: data)],
    ),
  );
  return doc.save();
}

/// A blank Form 7: the same chrome, certification sentence and review table
/// as [buildForm7Pdf], with the presenter and title lines ruled.
Future<Uint8List> buildForm7Blank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => [_page(FormText(form7Template))],
    ),
  );
  return doc.save();
}
