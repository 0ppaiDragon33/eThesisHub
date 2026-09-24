import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';

import '../pdf_text.dart';

final tpl = FormTemplate(
  formId: 'test',
  title: 'Test form',
  blocks: const [
    FormBlock(id: 'greeting', label: 'Greeting', defaultText: 'Sir/Madam:'),
    FormBlock(id: 'signer', label: 'Signer', kind: BlockKind.blank),
  ],
  layout: (t) => [pw.Text(t.of('greeting')), blankOr(t, 'signer')],
);

void main() {
  // The forms embed Source Serif 4 via rootBundle, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prints the form wording when nothing is edited', () async {
    final text = extractPdfText(await buildFormPdf(tpl, const {}));
    expect(text, contains('Sir/Madam:'));
  });

  test('prints an edited block instead of its default', () async {
    final text = extractPdfText(
        await buildFormPdf(tpl, const {'greeting': 'Dear Dean Reyes:'}));
    expect(text, contains('Dear Dean Reyes:'));
    expect(text, isNot(contains('Sir/Madam:')));
  });

  test('a filled blank prints its text', () async {
    final text = extractPdfText(
        await buildFormPdf(tpl, const {'signer': 'MARIA SANTOS'}));
    expect(text, contains('MARIA SANTOS'));
  });
}
