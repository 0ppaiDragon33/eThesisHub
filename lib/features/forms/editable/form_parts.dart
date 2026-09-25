import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

// Blocks and layout shared by the converted forms. The letter-shaped forms
// (3, 4a, 4b, 5a) open with the same heading, address and greeting and close
// with the same Recommending/Approved chain, so those live here once.

const _body = pw.TextStyle(fontSize: 11);

/// The editable part of every form's heading: its code and its title. The
/// institutional letterhead above them stays fixed (spec E10).
List<FormBlock> formHeadBlocks({
  required String rdCode,
  required String formTitle,
}) => [
  FormBlock(id: 'rdCode', label: 'Form code', defaultText: rdCode),
  FormBlock(id: 'formTitle', label: 'Form title', defaultText: formTitle),
];

/// Heading, date, address and greeting of a letter-shaped form.
List<FormBlock> letterOpeningBlocks({
  required String rdCode,
  required String formTitle,
}) => [
  ...formHeadBlocks(rdCode: rdCode, formTitle: formTitle),
  const FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
  const FormBlock(
    id: 'dateLabel',
    label: 'Label under the date',
    defaultText: 'Date',
  ),
  const FormBlock(
    id: 'addressee',
    label: 'Addressed to',
    defaultText: 'The Dean',
  ),
  FormBlock(
    id: 'addressCollege',
    label: 'Address: college',
    defaultText: 'College of ${'_' * 20}',
  ),
  const FormBlock(
    id: 'addressUniversity',
    label: 'Address: university',
    defaultText: 'Iloilo State University of Fisheries Science and Technology',
  ),
  const FormBlock(
    id: 'addressCity',
    label: 'Address: town',
    defaultText: 'Barotac Nuevo, Iloilo',
  ),
  const FormBlock(
    id: 'salutation',
    label: 'Greeting',
    defaultText: 'Sir/Madam:',
  ),
];

/// The Recommending Approval / Approved chain a letter-shaped form ends on.
/// Signature names default to empty, as the printed forms leave them.
const List<FormBlock> letterApprovalBlocks = [
  FormBlock(
    id: 'recommendingHeading',
    label: 'Recommending heading',
    defaultText: 'Recommending Approval:',
  ),
  FormBlock(id: 'coordinator', label: 'Research Coordinator: name'),
  FormBlock(
    id: 'coordinator.role',
    label: 'Research Coordinator: title',
    defaultText: 'College Research Coordinator',
  ),
  FormBlock(
    id: 'approvedHeading',
    label: 'Approval heading',
    defaultText: 'Approved:',
  ),
  FormBlock(id: 'dean', label: 'Dean: name'),
  FormBlock(
    id: 'dean.role',
    label: 'Dean: title',
    defaultText: 'Dean, ________',
  ),
];

/// A labelled field's two blocks: its label, and its value (a blank).
List<FormBlock> fieldBlocks(String id, String label) => [
  FormBlock(id: '$id.label', label: '$label (label)', defaultText: label),
  FormBlock(id: id, label: label, kind: BlockKind.blank),
];

/// The top of a letter-shaped form, down to the greeting. [college], when
/// the app knows it, fills the college line as the filled form always has.
List<pw.Widget> letterOpening(FormText t, {String college = ''}) => [
  formChrome(rdCode: t.of('rdCode'), formTitle: t.of('formTitle')),
  pw.SizedBox(height: 16),
  pw.Align(
    alignment: pw.Alignment.centerRight,
    child: blankOr(t, 'date', width: 140, style: _body),
  ),
  pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Text(t.of('dateLabel'), style: const pw.TextStyle(fontSize: 8)),
  ),
  pw.SizedBox(height: 16),
  pw.Text(t.of('addressee'), style: _body),
  pw.Text(
    college.isEmpty ? t.of('addressCollege') : 'College of $college',
    style: _body,
  ),
  pw.Text(t.of('addressUniversity'), style: _body),
  pw.Text(t.of('addressCity'), style: _body),
  pw.SizedBox(height: 12),
  pw.Text(t.of('salutation'), style: _body),
  pw.SizedBox(height: 10),
];

/// The Recommending Approval / Approved chain at the foot of a letter-shaped
/// form. [college], when the app knows it, names the Dean's college.
List<pw.Widget> letterApproval(FormText t, {String college = ''}) => [
  pw.Text(
    t.of('recommendingHeading'),
    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
  ),
  signableLine(t.of('coordinator'), t.of('coordinator.role')),
  pw.Text(
    t.of('approvedHeading'),
    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
  ),
  signableLine(
    t.of('dean'),
    college.isEmpty ? t.of('dean.role') : 'Dean, $college',
  ),
];

/// The reasons a change-of-adviser or change-of-title letter gives: one
/// paragraph the student writes, not three numbered reasons.
const FormBlock reasonsBlock = FormBlock(
  id: 'reasons',
  label: 'Reasons',
  kind: BlockKind.blank,
  multiline: true,
);

/// [reasonsBlock] on the page. Blank, it prints the three ruled lines the
/// paper form leaves for it; written, it prints the paragraph, wrapped to
/// the same width.
List<pw.Widget> reasonsParagraph(FormText t) => [
  if (t.isBlank('reasons'))
    for (var i = 0; i < 3; i++)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: ruledLine(width: 460),
      )
  else
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: blankOr(t, 'reasons', width: 460, style: _body),
    ),
];
