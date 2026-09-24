import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/editable/form_templates.dart';
import 'package:ethesishub/features/forms/form3_pdf.dart';
import 'package:ethesishub/features/forms/form4a_pdf.dart';
import 'package:ethesishub/features/forms/form4b_pdf.dart';
import 'package:ethesishub/features/forms/form5a_pdf.dart';
import 'package:ethesishub/features/forms/form5b_pdf.dart';
import 'package:ethesishub/features/forms/form5c_pdf.dart';
import 'package:ethesishub/features/forms/form7_pdf.dart';
import 'package:ethesishub/features/forms/form8_pdf.dart';

import '../pdf_text.dart';

/// Each converted form's official blank. A new copy of the form must start
/// out printing exactly like it. Each conversion task adds its form here.
final Map<String, Future<Uint8List> Function()> officialBlanks = {
  'form3': buildForm3Blank,
  'form4a': buildForm4aBlank,
  'form4b': buildForm4bBlank,
  'form5a': buildForm5aBlank,
  'form5b': buildForm5bBlank,
  'form5c': buildForm5cBlank,
  'form7': buildForm7Blank,
  'form8': buildForm8Blank,
};

void main() {
  // The forms embed Source Serif 4 via rootBundle, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all nine forms can be edited as copies', () {
    expect(formTemplates.keys.toSet(), {
      'form1', 'form3', 'form4a', 'form4b', 'form5a', 'form5b', 'form5c',
      'form7', 'form8',
    });
    expect(officialBlanks.keys.toSet(), {
      'form3', 'form4a', 'form4b', 'form5a', 'form5b', 'form5c', 'form7',
      'form8',
    }, reason: 'every form with an official blank is checked against it');
  });

  for (final template in formTemplates.values) {
    group(template.formId, () {
      test('every block id is unique', () {
        final ids = template.blocks.map((b) => b.id).toList();
        expect(ids.toSet().length, ids.length);
      });

      // A block the layout never reads is a field the editor offers that
      // changes nothing on the page.
      test('every block reaches the page', () {
        final text = FormText(template);
        template.layout(text);
        expect(text.read, template.blocks.map((b) => b.id).toSet());
      });

      test('the form title can be edited', () async {
        final text = extractPdfText(await buildFormPdf(
            template, const {'formTitle': 'EDITED TITLE 42'}));
        expect(text, contains('EDITED TITLE 42'));
      });

      final blank = officialBlanks[template.formId];
      if (blank != null) {
        test('a new copy prints exactly like the official blank', () async {
          expect(
            extractPdfText(await buildFormPdf(template, const {})),
            extractPdfText(await blank()),
          );
        });
      }
    });
  }
}
