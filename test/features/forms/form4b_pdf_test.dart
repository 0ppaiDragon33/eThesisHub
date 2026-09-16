import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/forms/form4b_pdf.dart';

import 'pdf_text.dart';

void main() {
  // The forms embed Source Serif 4 via rootBundle, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('carries the chrome and the form title', () async {
    final text = extractPdfText(await buildForm4bBlank());

    expect(text, contains('RD-35-06/24-04'));
    expect(text, contains('Change of Undergraduate Thesis Title'));
  });

  test('renders the request letter, blank only, no crash, no "null"',
      () async {
    final bytes = await buildForm4bBlank();
    final text = extractPdfText(bytes);

    expect(bytes, isNotEmpty);
    expect(text, isNot(contains('null')));
    expect(text, contains('Noted'));
    expect(text, contains('Thesis Adviser'));
  });
}
