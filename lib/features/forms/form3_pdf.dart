import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_parts.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form3_data.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

const _bodyStyle = pw.TextStyle(fontSize: 11);

/// Form 3's text, block by block, for an editable copy (spec 2026-09-24).
/// Every string on the page below the letterhead comes from here; the
/// official blank and filled letters read it unedited, so they print as
/// they always have.
final FormTemplate form3Template = FormTemplate(
  formId: 'form3',
  title: 'Form 3 — Request to Convene the Panel for Pre-Oral Defense',
  blocks: [
    ...letterOpeningBlocks(
      rdCode: 'RD-33-06/24-04',
      formTitle:
          'Form 3. Request to Convene the Thesis Panel Members for '
          'Pre-Oral Defense',
    ),
    const FormBlock(
      id: 'request',
      label: 'Request',
      multiline: true,
      defaultText:
          'I would like to request the Undergraduate Thesis Panel '
          'Members consisting of:',
    ),
    for (var i = 1; i <= 3; i++)
      FormBlock(
        id: 'panel.$i',
        label: 'Panel member $i',
        kind: BlockKind.blank,
      ),
    const FormBlock(
      id: 'convene',
      label: 'Purpose',
      multiline: true,
      defaultText: 'To convene and deliberate on the proposal of',
    ),
    const FormBlock(
      id: 'presenters',
      label: 'Presenters',
      kind: BlockKind.blank,
    ),
    const FormBlock(
      id: 'entitled',
      label: 'Before the title',
      defaultText: 'entitled',
    ),
    const FormBlock(
      id: 'title',
      label: 'Thesis title',
      kind: BlockKind.blank,
      multiline: true,
    ),
    const FormBlock(id: 'onWord', label: 'Before the date', defaultText: 'on'),
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
      defaultText: '(Place)${' ' * 45}(Time)',
    ),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this request is highly appreciated.',
    ),
    const FormBlock(
      id: 'valediction',
      label: 'Sign-off',
      defaultText: 'Very truly yours,',
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
/// an editable copy. `data == null` is the template and copy case.
///
/// Where the filled letter prints app data (presenters, panel, title, date,
/// place, time, college) the data wins; otherwise the block prints: its
/// typed text, or a ruled line while blank.
pw.Widget _page(FormText t, {Form3Data? data}) {
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
      ...letterOpening(t, college: college),
      pw.Text(t.of('request'), style: _bodyStyle),
      pw.SizedBox(height: 8),
      if (panel != null)
        for (final name in panel)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(name, style: _bodyStyle),
          )
      else
        for (var i = 1; i <= 3; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: blankOr(t, 'panel.$i', width: 260, style: _bodyStyle),
          ),
      pw.SizedBox(height: 8),
      pw.Text('${t.of('convene')} ${presenters ?? ''}', style: _bodyStyle),
      if (presenters == null)
        blankOr(t, 'presenters', width: 220, style: _bodyStyle),
      pw.SizedBox(height: 4),
      pw.Text(t.of('entitled'), style: _bodyStyle),
      dataOr(title, t, 'title', width: 400, style: _bodyStyle),
      pw.SizedBox(height: 8),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('${t.of('onWord')} ', style: _bodyStyle),
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
        ],
      ),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('${t.of('atWord')} ', style: _bodyStyle),
          dataOr(
            scheduledAt == null
                ? null
                : '${scheduledAt.hour.toString().padLeft(2, '0')}:'
                      '${scheduledAt.minute.toString().padLeft(2, '0')}',
            t,
            'time',
            width: 100,
            style: _bodyStyle,
          ),
          pw.Expanded(child: pw.SizedBox()),
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
        child: signableLine(t.of('adviser'), t.of('adviser.role')),
      ),
      pw.SizedBox(height: 8),
      ...letterApproval(t, college: college),
    ],
  );
}

/// Generates Form 3 — Request to Convene the Thesis Panel Members for
/// Pre-Oral Defense — as a PDF. `compress: false` keeps the content
/// streams text-greppable; see `form1_pdf.dart` for why that matters.
Future<Uint8List> buildForm3Pdf(Form3Data data) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form3Template), data: data),
    ),
  );
  return doc.save();
}

/// A blank Form 3: the same chrome and letter body as [buildForm3Pdf],
/// with every variable clause a ruled line. It is meant to be printed and
/// completed by hand, the way this letter is used before a defence exists
/// in the app at all.
Future<Uint8List> buildForm3Blank() async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => _page(FormText(form3Template)),
    ),
  );
  return doc.save();
}
