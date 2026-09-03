import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/forms/form4a_pdf.dart';

import 'pdf_text.dart';

void main() {
  test('carries the chrome and the form title', () async {
    final text = extractPdfText(await buildForm4aBlank());

    expect(text, contains('RD-34-06/24-04'));
    expect(text, contains('Change of Undergraduate Thesis Adviser'));
  });

  test('renders the request letter, blank only, no crash, no "null"',
      () async {
    final bytes = await buildForm4aBlank();
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
    expect(text, contains('Nominated Adviser'));
    expect(text, contains('Former Adviser'));
    expect(text, contains('Conforme'));
  });
}
