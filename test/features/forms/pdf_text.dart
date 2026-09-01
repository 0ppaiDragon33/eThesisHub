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
/// The contract is "what the page shows": PDF string-literal syntax
/// backslash-escapes `(`, `)` and `\` inside a `Tj`/`TJ` operand, so the raw
/// capture is unescaped back to plain characters before it is returned. A
/// caller asserting on rendered text should never need to know that the
/// operand it came from was PDF syntax.
///
/// Shared by every form's test suite so all three assert the same way.
String extractPdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final literal = RegExp(r'\(((?:\\.|[^()\\])*)\)');
  final escape = RegExp(r'\\(.)');
  final buffer = StringBuffer();
  for (final match in literal.allMatches(raw)) {
    // Unescape in one pass over the captured group — `\\`, `\(`, `\)` all
    // collapse to their single literal character. A two-pass replace (fix
    // `\(` then fix `\\`) would turn a genuine `\\(` into `((`; matching
    // `\` + any one character at a time and always taking that one
    // character avoids that ordering trap entirely.
    final unescaped =
        match.group(1)!.replaceAllMapped(escape, (m) => m.group(1)!);
    buffer.write(unescaped);
    buffer.write(' ');
  }
  return buffer.toString();
}
