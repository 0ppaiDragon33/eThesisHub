import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ethesishub/features/forms/form_chrome.dart';

import 'pdf_text.dart';

Future<Uint8List> renderChrome({
  required String rdCode,
  required String formTitle,
  String? reference,
}) async {
  // compress: false, exactly as every real form does — otherwise the text
  // operators are Flate-compressed and nothing below can assert on them.
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => formChrome(
        rdCode: rdCode,
        formTitle: formTitle,
        reference: reference,
      ),
    ),
  );
  return Uint8List.fromList(await doc.save());
}

void main() {
  test('the chrome carries the institution block', () async {
    final text = extractPdfText(
      await renderChrome(rdCode: 'RD-30-06/24-04', formTitle: 'Form 1. X'),
    );

    expect(text, contains('Republic of the Philippines'));
    expect(text, contains('ILOILO STATE UNIVERSITY'));
    expect(text, contains('RESEARCH AND DEVELOPMENT'));
    expect(text, contains('research@isufst.edu.ph'));
  });

  // Each form has its OWN RD code — Form 1 is RD-30, Form 5c is RD-37,
  // Form 8 is RD-39 — so this must be a parameter, never a constant.
  test('the RD code and form title come from the caller', () async {
    final text = extractPdfText(await renderChrome(
      rdCode: 'RD-37-06/24-04',
      formTitle: 'Form 5c. Evaluation Guide',
    ));

    expect(text, contains('RD-37-06/24-04'));
    expect(text, contains('Form 5c. Evaluation Guide'));
    expect(text, isNot(contains('RD-30')));
  });

  test('the reference is optional and omitted when absent', () async {
    final with_ = extractPdfText(await renderChrome(
        rdCode: 'RD-30-06/24-04', formTitle: 'Form 1. X', reference: 'ABC123'));
    expect(with_, contains('ABC123'));

    final without = extractPdfText(await renderChrome(
        rdCode: 'RD-39-06/24-04', formTitle: 'Form 8. Y'));
    expect(without, isNot(contains('Ref.')));
  });

  test('monthName covers every month, one-indexed', () {
    expect(monthName(1), 'January');
    expect(monthName(12), 'December');
  });
}
