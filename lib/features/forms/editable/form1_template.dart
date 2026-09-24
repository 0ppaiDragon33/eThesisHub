import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// How many researcher signature lines the blank Form 1 offers.
const int kForm1ResearcherSlots = 5;

/// How many panel member Conforme lines the blank Form 1 offers.
const int kForm1PanelSlots = 3;

const _body = pw.TextStyle(fontSize: 11);
const _name = pw.TextStyle(fontSize: 11.5);
const _heading = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
const _role = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

/// Form 1 as a blank anyone can fill in and reword in the app.
///
/// Not the official filled Form 1 (`form1_pdf.dart`), which is built from a
/// thesis's live nominations and stays as it is. This one has fixed slots,
/// underscores where a sentence has a blank in it, and no
/// "Electronically completed" notice, since a hand-edited copy is not.
/// The letterhead lines are fixed; everything below them is editable.
final FormTemplate form1Template = FormTemplate(
  formId: 'form1',
  title: 'Form 1 — Nomination of Thesis Adviser and Panel Members',
  blocks: [
    const FormBlock(
        id: 'rdCode', label: 'Form code', defaultText: 'RD-30-06/24-04'),
    const FormBlock(
      id: 'formTitle',
      label: 'Form title',
      defaultText: 'Form 1. Nomination of Thesis Adviser and Panel Members',
    ),
    const FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
    const FormBlock(
        id: 'dateLabel', label: 'Label under the date', defaultText: 'Date'),
    const FormBlock(
        id: 'addressee', label: 'Addressed to', defaultText: 'The Dean'),
    const FormBlock(
      id: 'addressCollege',
      label: 'Address: college',
      defaultText: 'College of ______________________',
    ),
    const FormBlock(
      id: 'addressUniversity',
      label: 'Address: university',
      defaultText:
          'Iloilo State University of Fisheries Science and Technology',
    ),
    const FormBlock(
      id: 'addressCity',
      label: 'Address: town',
      defaultText: 'Barotac Nuevo, Iloilo',
    ),
    const FormBlock(
        id: 'salutation', label: 'Greeting', defaultText: 'Sir/Madam:'),
    const FormBlock(
      id: 'adviserParagraph',
      label: 'Adviser paragraph',
      multiline: true,
      defaultText:
          'I/We have the honor to nominate Prof./Inst. '
          '______________________ to be my/our Undergraduate Thesis Adviser '
          'this __________ semester, Academic Year ______________.',
    ),
    const FormBlock(
      id: 'panelParagraph',
      label: 'Panel paragraph',
      multiline: true,
      defaultText:
          'Furthermore, I am/we are nominating Prof./Inst. '
          '______________________, ______________________ and '
          '______________________ to be my/our panel members.',
    ),
    const FormBlock(
      id: 'closing',
      label: 'Closing line',
      defaultText: 'Your approval on this matter is highly appreciated.',
    ),
    const FormBlock(
        id: 'valediction', label: 'Sign-off', defaultText: 'Very truly yours,'),
    for (var i = 1; i <= kForm1ResearcherSlots; i++) ...[
      FormBlock(
          id: 'researcher.$i',
          label: 'Researcher $i: name',
          kind: BlockKind.blank),
      FormBlock(
        id: 'researcher.$i.role',
        label: 'Researcher $i: role',
        defaultText: i == 1 ? 'Researcher · Group Leader' : 'Researcher',
      ),
    ],
    const FormBlock(
        id: 'conformeHeading',
        label: 'Conforme heading',
        defaultText: 'Conforme:'),
    const FormBlock(
        id: 'conforme.adviser',
        label: 'Thesis adviser: name',
        kind: BlockKind.blank),
    const FormBlock(
        id: 'conforme.adviser.role',
        label: 'Thesis adviser: role',
        defaultText: 'Thesis Adviser'),
    for (var i = 1; i <= kForm1PanelSlots; i++) ...[
      FormBlock(
          id: 'conforme.panel.$i',
          label: 'Panel member $i: name',
          kind: BlockKind.blank),
      FormBlock(
          id: 'conforme.panel.$i.role',
          label: 'Panel member $i: role',
          defaultText: 'Panel Member'),
    ],
    const FormBlock(
        id: 'recommendingHeading',
        label: 'Recommending heading',
        defaultText: 'Recommending Approval:'),
    const FormBlock(
        id: 'coordinator',
        label: 'Research Coordinator: name',
        kind: BlockKind.blank),
    const FormBlock(
        id: 'coordinator.role',
        label: 'Research Coordinator: title',
        defaultText: 'College Research Coordinator'),
    const FormBlock(
        id: 'approvedHeading',
        label: 'Approval heading',
        defaultText: 'Approved:'),
    const FormBlock(id: 'dean', label: 'Dean: name', kind: BlockKind.blank),
    const FormBlock(
        id: 'dean.role',
        label: 'Dean: title',
        defaultText: 'Dean, College of ______________'),
    const FormBlock(
      id: 'coreValues',
      label: 'Footer',
      defaultText:
          'Integrity  ·  Social Justice  ·  Discipline  ·  Academic Excellence',
    ),
  ],
  layout: _layout,
);

List<pw.Widget> _layout(FormText t) => [
      formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
      pw.SizedBox(height: 12),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: blankOr(t, 'date', width: 140, style: _body),
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('dateLabel'),
            style: const pw.TextStyle(fontSize: 8)),
      ),
      pw.SizedBox(height: 10),
      pw.Text(t.of('addressee'), style: _body),
      pw.Text(t.of('addressCollege'), style: _body),
      pw.Text(t.of('addressUniversity'), style: _body),
      pw.Text(t.of('addressCity'), style: _body),
      pw.SizedBox(height: 10),
      pw.Text(t.of('salutation'), style: _body),
      pw.SizedBox(height: 6),
      _indented(t.of('adviserParagraph')),
      pw.SizedBox(height: 6),
      _indented(t.of('panelParagraph')),
      pw.SizedBox(height: 6),
      _indented(t.of('closing')),
      pw.SizedBox(height: 12),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t.of('valediction'), style: _body),
      ),
      for (var i = 1; i <= kForm1ResearcherSlots; i++)
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(height: 18),
              blankOr(t, 'researcher.$i', width: 200, style: _name),
              pw.Text(t.of('researcher.$i.role'), style: _role),
            ],
          ),
        ),
      pw.SizedBox(height: 14),
      pw.Text(t.of('conformeHeading'), style: _heading),
      _signatureSlot(t, 'conforme.adviser'),
      for (var i = 1; i <= kForm1PanelSlots; i++)
        _signatureSlot(t, 'conforme.panel.$i'),
      pw.Text(t.of('recommendingHeading'), style: _heading),
      _signatureSlot(t, 'coordinator'),
      pw.Text(t.of('approvedHeading'), style: _heading),
      _signatureSlot(t, 'dean'),
      pw.SizedBox(height: 8),
      pw.Text(
        t.of('coreValues'),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    ];

pw.Widget _indented(String paragraph) => pw.Padding(
      padding: const pw.EdgeInsets.only(left: 30),
      child: pw.Text(paragraph,
          style: _body, textAlign: pw.TextAlign.justify),
    );

/// A name over its role: a ruled line where the name goes until one is
/// typed. The role is the block `'$id.role'`.
pw.Widget _signatureSlot(FormText t, String id) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 22),
          blankOr(t, id, width: 220, style: _name),
          pw.Text(t.of('$id.role'), style: _role),
        ],
      ),
    );
