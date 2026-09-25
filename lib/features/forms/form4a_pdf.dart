import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);
const _noteStyle = pw.TextStyle(fontSize: 8, color: PdfColors.grey600);

/// Form 4a's text, block by block, for an editable copy.
final FormTemplate form4aTemplate = FormTemplate(
  formId: 'form4a',
  title: 'Form 4a — Change of Undergraduate Thesis Adviser',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-34-06/24-04',
      formTitle: 'Form 4a. Change of Undergraduate Thesis Adviser',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText:
          'I would like to request for the change of my '
          'undergraduate Thesis Adviser',
    ),
    const FormBlock(
      id: 'nominatedAdviser',
      label: 'Nominated adviser',
      kind: BlockKind.blank,
    ),
    const FormBlock(
      id: 'toWord',
      label: 'Between the names',
      defaultText: 'to',
    ),
    const FormBlock(
      id: 'nominatedLabel',
      label: 'Label under the nominated adviser',
      defaultText: '(Nominated Adviser)',
    ),
    const FormBlock(
      id: 'formerAdviser',
      label: 'Former adviser',
      kind: BlockKind.blank,
    ),
    const FormBlock(
      id: 'formerLabel',
      label: 'Label under the former adviser',
      defaultText: '(Former Adviser)',
    ),
    const FormBlock(
      id: 'reasonsLead',
      label: 'Before the reasons',
      defaultText: 'for the following reasons:',
    ),
    for (var i = 1; i <= 3; i++)
      FormBlock(id: 'reason.$i', label: 'Reason $i', kind: BlockKind.blank),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this matter is highly appreciated.',
    ),
    const FormBlock(
      id: 'valediction',
      label: 'Sign-off',
      defaultText: 'Respectfully yours,',
    ),
    const FormBlock(id: 'student', label: 'Student: name'),
    const FormBlock(
      id: 'student.role',
      label: 'Student: title',
      defaultText: 'Student',
    ),
    const FormBlock(
      id: 'conformeHeading',
      label: 'Conforme heading',
      defaultText: 'Conforme:',
    ),
    const FormBlock(id: 'nominated', label: 'Nominated adviser: name'),
    const FormBlock(
      id: 'nominated.role',
      label: 'Nominated adviser: title',
      defaultText: 'Nominated Adviser',
    ),
    const FormBlock(id: 'former', label: 'Former adviser: name'),
    const FormBlock(
      id: 'former.role',
      label: 'Former adviser: title',
      defaultText: 'Former Adviser',
    ),
    ...letterApprovalBlocks,
  ],
  layout: (t) => [_page(t)],
);

/// The printed page, for the blank template and an editable copy. Form 4a
/// has no filled version: the app tracks no adviser-reassignment workflow
/// (no former or nominated adviser, no reason for the change anywhere in
/// the data model), so the office prints this blank and completes it by
/// hand.
pw.Widget _page(FormText t) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...letterOpening(t),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          blankOr(t, 'nominatedAdviser', width: 260, style: _bodyStyle),
          pw.SizedBox(width: 6),
          pw.Text(t.of('toWord'), style: _bodyStyle),
        ],
      ),
      pw.SizedBox(height: 2),
      pw.Text(t.of('nominatedLabel'), style: _noteStyle),
      pw.SizedBox(height: 4),
      blankOr(t, 'formerAdviser', width: 260, style: _bodyStyle),
      pw.Text(t.of('formerLabel'), style: _noteStyle),
      pw.SizedBox(height: 10),
      pw.Text(t.of('reasonsLead'), style: _bodyStyle),
      pw.SizedBox(height: 6),
      for (var i = 1; i <= 3; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: blankOr(t, 'reason.$i', width: 460, style: _bodyStyle),
        ),
      pw.SizedBox(height: 10),
      pw.Text(t.of('closing'), style: _bodyStyle),
      pw.SizedBox(height: 16),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('valediction'), style: _bodyStyle),
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: signableLine(t.of('student'), t.of('student.role')),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        t.of('conformeHeading'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine(t.of('nominated'), t.of('nominated.role')),
      signableLine(t.of('former'), t.of('former.role')),
      ...letterApproval(t),
    ],
  );
}

/// Form 4a — Change of Undergraduate Thesis Adviser. Blank template only;
/// see [_page] for why there is no filled version.
Future<Uint8List> buildForm4aBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form4aTemplate)),
    ),
  );
  return doc.save();
}
