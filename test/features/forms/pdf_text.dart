import 'dart:convert';
import 'dart:typed_data';

/// The `pdf` package is a generator, not a parser — there is no
/// `PdfDocument.load`/text-extraction API in `pdf` or `printing`. What makes
/// text assertions possible at all is that every `buildFormNPdf` builds its
/// `pw.Document` with `compress: false`, so the content stream's `Tj`/`TJ`
/// text-showing operators are plain bytes rather than Flate-compressed ones.
///
/// The contract is "what the page shows". Two encodings have to be handled
/// to keep that promise:
///
/// * **Built-in fonts** (Helvetica) show text as parenthesized literals —
///   `(Hi Vargas)Tj` — whose bytes are the characters themselves. PDF string
///   syntax backslash-escapes `(`, `)` and `\`, so a raw capture is
///   unescaped before it is returned.
/// * **Embedded TrueType fonts** show text as hex-encoded glyph ids under
///   `Identity-H` — `[<00010002>]TJ` — which are indices into a subset, not
///   characters. `0001` is 'H' only because the font's `/ToUnicode` CMap
///   says so. Those are decoded through that CMap.
///
/// The second case is why this is not a two-line regex. Once the forms
/// embedded Source Serif 4 (so that em dashes and non-Latin-1 names stopped
/// silently vanishing), a naive parenthesized-literal grep returned the
/// CMap's own `(Adobe)` / `(UCS)` strings instead of the page's words.
///
/// Glyph ids are per-font — `0001` means something different in each subset
/// — so the active font is tracked through `/F5 12 Tf` operators and each
/// run is decoded with that font's own CMap. Merging the CMaps would decode
/// most documents into plausible nonsense.
///
/// Shared by every form's test suite so they all assert the same way.
String extractPdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final fonts = _toUnicodeByFont(raw);
  final buffer = StringBuffer();

  for (final stream in _streams(raw)) {
    // A CMap is not a page, and a font program is not a page. Content
    // streams are the ones that position and show text.
    if (stream.contains('begincmap') || !stream.contains('BT')) continue;

    Map<int, String>? active;
    for (final token in _showText.allMatches(stream)) {
      final selected = token.group(1);
      if (selected != null) {
        active = fonts[selected];
        continue;
      }

      final hex = token.group(2);
      if (hex != null) {
        buffer
          ..write(_decodeGlyphs(hex, active))
          ..write(' ');
        continue;
      }

      final literal = token.group(3);
      if (literal != null) {
        buffer
          ..write(literal.replaceAllMapped(_escape, (m) => m.group(1)!))
          ..write(' ');
      }
    }
  }

  return buffer.toString();
}

/// Font selection (`/F5 12 Tf`), a hex-encoded run, or a literal run — in
/// document order, so the active font is always the one most recently
/// selected. Hex and literal runs are matched wherever they appear inside a
/// content stream rather than only when glued to `Tj`, because `TJ` takes an
/// array and a run can sit behind kerning numbers and a `]`.
final _showText = RegExp(
  r'/(F\d+)\s+[\d.]+\s+Tf'
  r'|<([0-9A-Fa-f\s]+)>'
  r'|\(((?:\\.|[^()\\])*)\)',
);

/// Unescape in one pass — `\\`, `\(`, `\)` all collapse to their single
/// literal character. A two-pass replace (fix `\(` then fix `\\`) would turn
/// a genuine `\\(` into `((`; matching `\` plus any one character and always
/// taking that character avoids the ordering trap entirely.
final _escape = RegExp(r'\\(.)');

/// Every `stream ... endstream` payload, uncompressed by `compress: false`.
Iterable<String> _streams(String raw) sync* {
  final block = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true);
  for (final m in block.allMatches(raw)) {
    yield m.group(1)!;
  }
}

/// Maps each font resource name (`F5`) to its `/ToUnicode` CMap.
///
/// The font dictionary carries both the name it is selected by and the
/// object number of its CMap; the CMap's own stream holds the mapping. A
/// font with no `/ToUnicode` (a built-in) simply gets no entry, which is
/// what leaves the literal path below untouched.
Map<String, Map<int, String>> _toUnicodeByFont(String raw) {
  final result = <String, Map<int, String>>{};
  final font = RegExp(r'/Name\s*/(F\d+)');

  for (final m in font.allMatches(raw)) {
    // Search forward only to the end of this object, so a later font's
    // /ToUnicode is never attributed to this one.
    final end = raw.indexOf('endobj', m.start);
    final dict = raw.substring(m.start, end == -1 ? raw.length : end);
    final ref = RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(dict);
    if (ref == null) continue;

    final cmap = _objectStream(raw, int.parse(ref.group(1)!));
    if (cmap != null) result[m.group(1)!] = _parseCMap(cmap);
  }
  return result;
}

/// The stream payload of object [number], or null when it has none.
String? _objectStream(String raw, int number) {
  final obj = RegExp(
    '(?:^|[^0-9])$number\\s+0\\s+obj(.*?)endobj',
    dotAll: true,
  ).firstMatch(raw);
  if (obj == null) return null;

  final body = obj.group(1)!;
  final stream =
      RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true).firstMatch(body);
  return stream?.group(1);
}

/// Glyph id -> character, from a `/ToUnicode` CMap's `bfchar` and `bfrange`
/// sections.
///
/// `bfrange` is handled even though the `pdf` package currently emits only
/// `bfchar` for its subsets: the CMap format allows either, and a reader
/// that silently returns nothing for a valid document is worse than one that
/// costs a few extra lines.
Map<int, String> _parseCMap(String cmap) {
  final map = <int, String>{};
  final hex = RegExp(r'<([0-9A-Fa-f]+)>');

  for (final section
      in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(cmap)) {
    final codes = hex.allMatches(section.group(1)!).toList();
    for (var i = 0; i + 1 < codes.length; i += 2) {
      map[int.parse(codes[i].group(1)!, radix: 16)] =
          _fromUtf16(codes[i + 1].group(1)!);
    }
  }

  for (final section in RegExp(
    r'beginbfrange(.*?)endbfrange',
    dotAll: true,
  ).allMatches(cmap)) {
    final codes = hex.allMatches(section.group(1)!).toList();
    for (var i = 0; i + 2 < codes.length; i += 3) {
      final lo = int.parse(codes[i].group(1)!, radix: 16);
      final hi = int.parse(codes[i + 1].group(1)!, radix: 16);
      final dst = int.parse(codes[i + 2].group(1)!, radix: 16);
      for (var c = lo; c <= hi; c++) {
        map[c] = String.fromCharCode(dst + (c - lo));
      }
    }
  }

  return map;
}

/// A CMap destination is UTF-16BE, so it can be more than one code unit —
/// a character outside the BMP maps to a surrogate pair.
String _fromUtf16(String digits) {
  final units = <int>[];
  for (var i = 0; i + 3 < digits.length + 1; i += 4) {
    units.add(int.parse(digits.substring(i, i + 4), radix: 16));
  }
  return String.fromCharCodes(units);
}

/// Decode a run of 2-byte glyph ids through [map].
///
/// Without a map the run cannot be text this reader understands, so it
/// contributes nothing rather than leaking hex digits into an assertion.
/// Glyph 0 is `.notdef` and is skipped for the same reason.
String _decodeGlyphs(String hex, Map<int, String>? map) {
  if (map == null) return '';
  final digits = hex.replaceAll(RegExp(r'\s'), '');
  final out = StringBuffer();
  for (var i = 0; i + 3 < digits.length + 1; i += 4) {
    final code = int.tryParse(digits.substring(i, i + 4), radix: 16);
    if (code == null || code == 0) continue;
    out.write(map[code] ?? '');
  }
  return out.toString();
}
