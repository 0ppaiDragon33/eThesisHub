import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/forms/editable/form1_template.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/editable/form_templates.dart';

import '../pdf_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every block id is unique', () {
    final ids = form1Template.blocks.map((b) => b.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  // A block the layout never reads is a field the editor offers that
  // changes nothing on the page.
  test('every block reaches the page', () {
    final text = FormText(form1Template);
    form1Template.layout(text);
    expect(text.read, form1Template.blocks.map((b) => b.id).toSet());
  });

  test('offers five researcher lines and three panel lines', () {
    final ids = form1Template.blocks.map((b) => b.id).toSet();
    for (var i = 1; i <= kForm1ResearcherSlots; i++) {
      expect(ids, contains('researcher.$i'));
    }
    for (var i = 1; i <= kForm1PanelSlots; i++) {
      expect(ids, contains('conforme.panel.$i'));
    }
    expect(kForm1ResearcherSlots, 5);
    expect(kForm1PanelSlots, 3);
  });

  test('an unedited copy prints the form\'s own wording', () async {
    final text = extractPdfText(await buildFormPdf(form1Template, const {}));
    for (final phrase in [
      'Sir/Madam:',
      'Very truly yours,',
      'Conforme:',
      'Recommending Approval:',
      'Approved:',
      'RD-30-06/24-04',
    ]) {
      expect(text, contains(phrase), reason: phrase);
    }
  });

  test('leaves off the electronic-completion notice (ruling R4)', () async {
    final text = extractPdfText(await buildFormPdf(form1Template, const {}));
    expect(text, isNot(contains('Electronically completed')));
  });

  test('prints edited text in place of the wording it replaces', () async {
    final text = extractPdfText(await buildFormPdf(form1Template, const {
      'salutation': 'Dear Dean Reyes:',
      'researcher.1': 'MARIA SANTOS',
      'conforme.adviser': 'DR. JUAN CRUZ',
    }));
    expect(text, contains('Dear Dean Reyes:'));
    expect(text, contains('MARIA SANTOS'));
    expect(text, contains('DR. JUAN CRUZ'));
    expect(text, isNot(contains('Sir/Madam:')));
  });

  test('the registry finds Form 1 and nothing it does not have', () {
    expect(templateFor('form1'), same(form1Template));
    expect(templateFor('form99'), isNull);
  });
}
