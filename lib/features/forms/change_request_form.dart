import 'dart:typed_data';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/form4a_pdf.dart';
import 'package:ethesishub/features/forms/form4b_pdf.dart';

/// The filled Form 4a / 4b record for an approved change request: the
/// nominated/former adviser or the old/new title, plus the reasons, printed
/// onto the same template the editor uses (spec 2026-09-25 Task 8).
Future<Uint8List> buildChangeRequestPdf(
  ChangeRequest request, {
  required Thesis thesis,
}) {
  switch (request.type) {
    case ChangeRequestType.adviser:
      final newAdviser = request.newAdviserName!;
      final formerAdviser = request.formerAdviserName!;
      return buildFormPdf(form4aTemplate, {
        'nominatedAdviser': newAdviser,
        'formerAdviser': formerAdviser,
        'reasons': request.reasons,
        'nominated': newAdviser,
        'former': formerAdviser,
      });
    case ChangeRequestType.title:
      return buildFormPdf(form4bTemplate, {
        'oldTitle': thesis.workingTitle,
        'newTitle': request.newTitle!,
        'reasons': request.reasons,
      });
  }
}
