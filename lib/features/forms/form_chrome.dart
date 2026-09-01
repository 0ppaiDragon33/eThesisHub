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
            pw.Text('Republic of the Philippines',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              'ILOILO STATE UNIVERSITY OF FISHERIES SCIENCE AND TECHNOLOGY',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: formAccent,
              ),
            ),
            pw.Text('RESEARCH AND DEVELOPMENT',
                style: const pw.TextStyle(fontSize: 10)),
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
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
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
