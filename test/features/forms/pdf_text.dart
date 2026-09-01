import 'dart:convert';
import 'dart:typed_data';

/// The `pdf` package is a generator, not a parser — there is no
/// `PdfDocument.load`/text-extraction API in `pdf` or `printing`. What makes
/// text assertions possible at all is that every `buildFormNPdf` builds its
/// `pw.Document` with `compress: false`, so the content stream's `Tj`/`TJ`
/// text-showing operators are plain bytes rather than Flate-compressed ones.
/// This pulls every parenthesized literal string out of those operators, in
/// document order, and joins them with a space — a real (if crude) text
/// extraction, not a re-assertion of the smoke test.
///
/// Shared by every form's test suite so all three assert the same way.
String extractPdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final literal = RegExp(r'\(((?:\\.|[^()\\])*)\)');
  final buffer = StringBuffer();
  for (final match in literal.allMatches(raw)) {
    buffer.write(match.group(1));
    buffer.write(' ');
  }
  return buffer.toString();
}
