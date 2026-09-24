import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/editable/form_template.dart';

final tpl = FormTemplate(
  formId: 'test',
  title: 'Test form',
  blocks: const [
    FormBlock(id: 'greeting', label: 'Greeting', defaultText: 'Sir/Madam:'),
    FormBlock(id: 'date', label: 'Date', kind: BlockKind.blank),
    FormBlock(
        id: 'body', label: 'Body', defaultText: 'Hello.', multiline: true),
  ],
  layout: (t) => [pw.Text(t.of('greeting'))],
);

void main() {
  group('FormText', () {
    test('a block with no override reads its default', () {
      expect(FormText(tpl).of('greeting'), 'Sir/Madam:');
    });

    test('an override replaces the default', () {
      expect(FormText(tpl, {'greeting': 'Dear Dean:'}).of('greeting'),
          'Dear Dean:');
    });

    test('an emptied text block reads as empty, not as its default', () {
      expect(FormText(tpl, {'greeting': ''}).of('greeting'), '');
    });

    test('a blank with no text is blank; typed text is not', () {
      expect(FormText(tpl).isBlank('date'), isTrue);
      final filled = FormText(tpl, {'date': '1 May 2026'});
      expect(filled.isBlank('date'), isFalse);
      expect(filled.of('date'), '1 May 2026');
    });

    test('a blank holding only spaces still prints as a blank line', () {
      expect(FormText(tpl, {'date': '   '}).isBlank('date'), isTrue);
    });

    test('a text block is never blank, even when emptied', () {
      expect(FormText(tpl, {'greeting': ''}).isBlank('greeting'), isFalse);
    });

    test('an override for a block the template no longer has is ignored', () {
      expect(FormText(tpl, {'gone': 'x'}).of('greeting'), 'Sir/Madam:');
    });

    test('asking for a block the template does not have is a bug', () {
      expect(() => FormText(tpl).of('nope'), throwsArgumentError);
    });

    test('records every block the layout asked for', () {
      final t = FormText(tpl);
      t.of('greeting');
      t.isBlank('date');
      expect(t.read, {'greeting', 'date'});
    });
  });

  group('overridesFrom', () {
    test('keeps only blocks whose text differs from the default', () {
      expect(
        tpl.overridesFrom(
            {'greeting': 'Sir/Madam:', 'date': '1 May', 'body': 'Changed.'}),
        {'date': '1 May', 'body': 'Changed.'},
      );
    });

    test('drops ids the template does not have', () {
      expect(tpl.overridesFrom({'gone': 'x'}), isEmpty);
    });

    test('keeps an emptied text block, since empty is not the default', () {
      expect(tpl.overridesFrom({'greeting': ''}), {'greeting': ''});
    });
  });
}
