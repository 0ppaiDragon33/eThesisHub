import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/editable/form_templates.dart';

import '../pdf_text.dart';

/// Each converted form's official blank. A new copy of the form must start
/// out printing exactly like it. Each conversion task adds its form here.
final Map<String, Future<Uint8List> Function()> officialBlanks = {};

void main() {
  // The forms embed Source Serif 4 via rootBundle, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

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
