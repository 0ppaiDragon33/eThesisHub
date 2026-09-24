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

  group('dataOr and valueOr', () {
    final helperTpl = FormTemplate(
      formId: 'helper',
      title: 'Helper',
      blocks: const [
        FormBlock(id: 'venue', label: 'Venue', kind: BlockKind.blank),
        FormBlock(id: 'lead', label: 'Lead', defaultText: 'Lead text'),
      ],
      layout: (t) => [
        pw.Text(t.of('lead')),
        dataOr(null, t, 'venue'),
      ],
    );

    test('valueOr prefers app data, then typed text, then nothing', () {
      expect(valueOr('AVR', FormText(helperTpl), 'venue'), 'AVR');
      expect(valueOr('', FormText(helperTpl), 'venue'), '',
          reason: 'an empty value from the app is still the app\'s value');
      expect(valueOr(null, FormText(helperTpl, {'venue': 'Room 2'}), 'venue'),
          'Room 2');
      expect(valueOr(null, FormText(helperTpl), 'venue'), isNull);
    });

    test('dataOr prints app data over anything typed', () async {
      final tpl = FormTemplate(
        formId: 'helper2',
        title: 'Helper',
        blocks: helperTpl.blocks,
        layout: (t) => [dataOr('From the app', t, 'venue')],
      );
      final text = extractPdfText(
          await buildFormPdf(tpl, const {'venue': 'Typed venue'}));
      expect(text, contains('From the app'));
      expect(text, isNot(contains('Typed venue')));
    });

    test('dataOr without app data prints the typed text', () async {
      final text = extractPdfText(
          await buildFormPdf(helperTpl, const {'venue': 'Typed venue'}));
      expect(text, contains('Typed venue'));
    });
  });
}
