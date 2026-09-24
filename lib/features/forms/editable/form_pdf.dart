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

/// A block's text, or a ruled line while it is an empty blank.
pw.Widget blankOr(
  FormText text,
  String id, {
  double width = 160,
  pw.TextStyle? style,
}) {
  if (text.isBlank(id)) return ruledLine(width: width);
  return pw.Text(text.of(id), style: style);
}
