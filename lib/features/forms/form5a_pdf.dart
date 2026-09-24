import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form5a_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 5a's text, block by block, for an editable copy.
final FormTemplate form5aTemplate = FormTemplate(
  formId: 'form5a',
  title: 'Form 5a — Request for Final Oral Defense',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-36-06/24-04',
      formTitle: 'Form 5a. Request for Final Oral Defense',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText:
          'I have the honor to request for the final oral defense '
          'of my undergraduate thesis entitled',
    ),
    const FormBlock(
      id: 'title',
      label: 'Thesis title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(
      id: 'scheduleLead',
      label: 'Before the schedule',
      defaultText: 'The final oral defense will be conducted on',
    ),
    const FormBlock(
      id: 'scheduledDate',
      label: 'Defense date',
      kind: BlockKind.blank,
    ),
    const FormBlock(id: 'inWord', label: 'Before the place', defaultText: 'in'),
    const FormBlock(id: 'venue', label: 'Place', kind: BlockKind.blank),
    const FormBlock(id: 'atWord', label: 'Before the time', defaultText: 'at'),
    const FormBlock(id: 'time', label: 'Time', kind: BlockKind.blank),
    FormBlock(
      id: 'placeTimeLabel',
      label: 'Labels under place and time',
      defaultText: '(Place)${' ' * 50}(Time)',
    ),
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

/// The whole printed page, shared by a real letter, the blank template and
/// an editable copy. `data == null` is the template and copy case. Where
/// the filled letter prints app data (title, date, place, time, college)
/// the data wins; otherwise the block prints.
pw.Widget _page(FormText t, {Form5aData? data}) {
  final title = data?.title.isNotEmpty == true ? data!.title : null;
  final scheduledAt = data?.scheduledAt;
  final venue = data?.venue.isNotEmpty == true ? data!.venue : null;
  final college = data?.college ?? '';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      ...letterOpening(t, college: college),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      dataOr(
        title == null ? null : '"$title".',
        t,
        'title',
        width: 400,
        style: _bodyStyle,
      ),
      pw.SizedBox(height: 8),
      pw.Text(t.of('scheduleLead'), style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          dataOr(
            scheduledAt == null
                ? null
                : '${scheduledAt.day} ${monthName(scheduledAt.month)} '
                      '${scheduledAt.year}',
            t,
            'scheduledDate',
            width: 100,
            style: _bodyStyle,
          ),
          pw.Text(' ${t.of('inWord')} ', style: _bodyStyle),
          pw.Expanded(child: dataOr(venue, t, 'venue', style: _bodyStyle)),
          pw.Text(' ${t.of('atWord')} ', style: _bodyStyle),
          dataOr(
            scheduledAt == null
                ? null
                : '${scheduledAt.hour.toString().padLeft(2, '0')}:'
                      '${scheduledAt.minute.toString().padLeft(2, '0')}',
            t,
            'time',
            width: 80,
            style: _bodyStyle,
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        t.of('placeTimeLabel'),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 12),
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
      ...letterApproval(t, college: college),
    ],
  );
}

/// Generates Form 5a — Request for Final Oral Defense — as a PDF.
Future<Uint8List> buildForm5aPdf(Form5aData data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5aTemplate), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 5a: the same chrome and letter body as [buildForm5aPdf],
/// with every variable clause a ruled line.
Future<Uint8List> buildForm5aBlank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form5aTemplate)),
    ),
  );
  return doc.save();
}
