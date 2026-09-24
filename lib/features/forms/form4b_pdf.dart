import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 4b's text, block by block, for an editable copy.
final FormTemplate form4bTemplate = FormTemplate(
  formId: 'form4b',
  title: 'Form 4b — Change of Undergraduate Thesis Title',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-35-06/24-04',
      formTitle: 'Form 4b. Change of Undergraduate Thesis Title',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText:
          'I would like to request for the change of my '
          'undergraduate Thesis Title',
    ),
    const FormBlock(
      id: 'oldTitle',
      label: 'Current title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(
      id: 'toWord',
      label: 'Between the titles',
      defaultText: 'to',
    ),
    const FormBlock(
      id: 'newTitle',
      label: 'New title',
      kind: BlockKind.blank,
      multiline: true,
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
      id: 'notedHeading',
      label: 'Noted heading',
      defaultText: 'Noted:',
    ),
    const FormBlock(id: 'adviser', label: 'Thesis Adviser: name'),
    const FormBlock(
      id: 'adviser.role',
      label: 'Thesis Adviser: title',
      defaultText: 'Thesis Adviser',
    ),
    ...letterApprovalBlocks,
  ],
  layout: (t) => [_page(t)],
);

/// The printed page, for the blank template and an editable copy. Form 4b
/// has no filled version, for the same reason as Form 4a: the app has no
/// "change the approved title" workflow (title changes go through the
/// multi-round title defence instead).
pw.Widget _page(FormText t) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...letterOpening(t),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 6),
      blankOr(t, 'oldTitle', width: 460, style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Text(t.of('toWord'), style: _bodyStyle),
      pw.SizedBox(height: 6),
      blankOr(t, 'newTitle', width: 460, style: _bodyStyle),
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
        t.of('notedHeading'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      signableLine(t.of('adviser'), t.of('adviser.role')),
      ...letterApproval(t),
    ],
  );
}

/// Form 4b — Change of Undergraduate Thesis Title. Blank template only;
/// see [_page] for why there is no filled version.
Future<Uint8List> buildForm4bBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form4bTemplate)),
    ),
  );
  return doc.save();
}
