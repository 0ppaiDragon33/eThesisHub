import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The house blue, shared by every form's rule and institution line.
const formAccent = PdfColor.fromInt(0xFF0B5FA5);

/// The letterhead every ISUFST research form carries, identically.
///
/// Extracted from Form 1 when Form 5c and Form 8 arrived — three copies of
/// the same address block is three places to fix it. Form 1 was moved onto
/// this FIRST, so its existing tests prove the extraction changed no
/// rendering before either new form depended on it.
///
/// [rdCode] differs per form (Form 1 is RD-30-06/24-04, Form 5c is
/// RD-37-06/24-04, Form 8 is RD-39-06/24-04) and is therefore a parameter,
/// not a constant.
///
/// [reference] is Form 1's short thesis id. Forms 5c and 8 have no such
/// field on the printed original, so it is optional and the row collapses
/// to just the title when it is absent.
pw.Widget formChrome({
  required String rdCode,
  required String formTitle,
  String? reference,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        rdCode,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 6),
      pw.Center(
        child: pw.Column(
          children: [
            pw.Text(
              'Republic of the Philippines',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              'ILOILO STATE UNIVERSITY OF FISHERIES SCIENCE AND TECHNOLOGY',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: formAccent,
              ),
            ),
            pw.Text(
              'RESEARCH AND DEVELOPMENT',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              'Tiwi, Barotac Nuevo, Iloilo | research@isufst.edu.ph',
              style: const pw.TextStyle(fontSize: 8.5),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Container(height: 2, color: formAccent),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            formTitle,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          if (reference != null)
            pw.Text(
              'Ref. $reference',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
        ],
      ),
    ],
  );
}

/// One-indexed, so `monthName(1)` is January. Shared rather than repeated
/// because three forms print a date.
String monthName(int m) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][m - 1];

/// A list of names read as one comma-joined, "and"-terminated sentence
/// fragment. Originated in Form 1 (the panel members read as one flowing
/// clause in the nomination letter) and hoisted here, alongside
/// `formChrome`, when Form 8 needed the identical join for its certificate
/// sentence — a pure, side-effect-free string helper belongs with the other
/// cross-form logic, not behind an import of whichever form happened to
/// write it first.
String panelSentence(List<String> panelNames) => panelNames.length <= 1
    ? panelNames.join()
    : '${panelNames.sublist(0, panelNames.length - 1).join(', ')} '
          'and ${panelNames.last}';

/// A name with clear space above it to sign into, and an optional status
/// line to its right. No rule under the name — the printed forms leave
/// the signing area blank, and this widget matches that on purpose.
///
/// Originated in Form 1 (`_signable`, for its Conforme / Recommending
/// Approval / Approved chain) and hoisted here when the letter-shaped
/// forms (3, 4a, 4b, 5a) needed the identical block for the same three
/// signatures every one of those letters ends with.
pw.Widget signableLine(String name, String role, {String? status}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          flex: 58,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 22),
              pw.Text(name, style: const pw.TextStyle(fontSize: 11.5)),
              pw.Text(
                role,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        if (status != null)
          pw.Expanded(
            flex: 42,
            child: pw.Text(
              status,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColor.fromInt(0xFF15803D),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A ruled blank of the given width, mid-line — for the underscore runs a
/// letter form prints where a value is written by hand (a name, a title,
/// a place). Distinct from a labelled field's full-width rule: this one
/// sits inline inside a sentence, so it takes only a width, no label.
///
/// Every letter-shaped blank template (3, 4a, 4b, 5a) rules its variable
/// clauses this way rather than printing literal underscore characters,
/// so the line the reader signs across is a real drawn rule and not a
/// string of `_` that reflows unpredictably with the surrounding prose.
pw.Widget ruledLine({double width = 160, double height = 12}) {
  return pw.Container(
    width: width,
    height: height,
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey600)),
    ),
  );
}

/// The ruled line a missing value prints as, in a labelled field. Shared
/// so every form's "the system does not hold this" blank looks identical
/// on the page, whatever form it appears on.
pw.Widget formRule({double? width, double height = 11}) => pw.Container(
  width: width,
  height: height,
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
  ),
);

/// A "Label: value" row. When [value] is null or empty, [formRule] prints
/// instead of the literal string "null" or a silent gap — a form built
/// with no data at all (a blank template) rules every field the same way.
///
/// Originated in Form 5c (`_field`, for its identifying header and its
/// SUMMARY block) and hoisted here when Form 5b needed the identical
/// header fields — Form 5c's own D60/D61 borrowed 5b's fields for its
/// header, so it was only a matter of time before the row that renders
/// them was needed by both.
pw.Widget formField(String label, String? value) {
  final hasValue = value != null && value.trim().isNotEmpty;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 170,
          child: pw.Text(
            '$label:',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(
          child: hasValue
              ? pw.Text(value, style: const pw.TextStyle(fontSize: 10.5))
              : formRule(),
        ),
      ],
    ),
  );
}
