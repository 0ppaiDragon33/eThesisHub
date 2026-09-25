import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/form_chrome.dart';

/// Renders [template] with a copy's [overrides] as a PDF: same page size,
/// margins, embedded font and uncompressed streams as every other form, so
/// `extractPdfText` can read it and it prints alongside them.
///
/// MultiPage, not Page: a `pw.Page` silently clips whatever does not fit,
/// and text a person has typed can run longer than the form's own wording.
Future<Uint8List> buildFormPdf(
  FormTemplate template,
  Map<String, String> overrides,
) async {
  final doc = pw.Document(compress: false, theme: await formTheme());
  final text = FormText(template, overrides);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (_) => template.layout(text),
    ),
  );
  return doc.save();
}

/// A block's text, or a ruled line of [width] × [height] while it is an
/// empty blank.
///
/// Typed text wraps within [width], the width of the line it replaces, so a
/// long entry in a row cannot push the row off the page. Short text keeps
/// its own natural width rather than filling [width], so it still hugs
/// whichever edge its parent aligns it to (a right-aligned date, a name in
/// an end-aligned column).
pw.Widget blankOr(
  FormText text,
  String id, {
  double width = 160,
  double height = 12,
  pw.TextStyle? style,
}) {
  if (text.isBlank(id)) return ruledLine(width: width, height: height);
  return pw.ConstrainedBox(
    constraints: pw.BoxConstraints(maxWidth: width),
    child: pw.Text(text.of(id), style: style),
  );
}

/// A value the app supplied, printed exactly as the official filled form
/// prints it. Without one, the block: its typed text, or a ruled line
/// while blank.
pw.Widget dataOr(
  String? value,
  FormText text,
  String id, {
  double width = 160,
  double height = 12,
  pw.TextStyle? style,
}) {
  if (value != null) return pw.Text(value, style: style);
  return blankOr(text, id, width: width, height: height, style: style);
}

/// For a labelled field or a summary row: the app's value when it supplied
/// one (even an empty one, which the field rules as a blank), otherwise the
/// block's typed text, otherwise null so the field rules a blank.
String? valueOr(String? value, FormText text, String id) =>
    value ?? (text.isBlank(id) ? null : text.of(id));
