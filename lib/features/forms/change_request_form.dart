import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/form4a_pdf.dart';
import 'package:ethesishub/features/forms/form4b_pdf.dart';
import 'package:ethesishub/features/forms/form_viewer.dart';

/// The filled Form 4a / 4b for a change request: the nominated/former
/// adviser or the old/new title, plus the reasons, printed onto the same
/// template the editor uses (spec 2026-09-25 Task 8). Shown to signers while
/// they decide and downloadable once approved.
///
/// [thesis] is optional: the old title is captured on the request at submit,
/// so a signer who may not read the thesis (a proposed new adviser) can
/// still open the form. It is only a fallback for older requests.
Future<Uint8List> buildChangeRequestPdf(
  ChangeRequest request, {
  Thesis? thesis,
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
      // By the time this request is `approved` the Dean's batch has already
      // overwritten thesis.workingTitle with the new title, so the original
      // title comes from the request's own oldTitle -- captured at submit
      // time -- with the live thesis field only as a fallback for requests
      // predating that field.
      return buildFormPdf(form4bTemplate, {
        'oldTitle': request.oldTitle ?? thesis?.workingTitle ?? '',
        'newTitle': request.newTitle!,
        'reasons': request.reasons,
      });
  }
}

/// "View Form 4a" / "View Form 4b" for a change request, on each card where
/// a signer accepts, declines, recommends, returns or approves it.
class ViewChangeRequestFormButton extends StatelessWidget {
  const ViewChangeRequestFormButton({
    super.key,
    required this.thesisId,
    required this.request,
  });

  final String thesisId;
  final ChangeRequest request;

  @override
  Widget build(BuildContext context) {
    final adviser = request.type == ChangeRequestType.adviser;
    return Wrap(
      children: [
        ViewFormButton(
          label: adviser ? 'View Form 4a' : 'View Form 4b',
          title: adviser
              ? 'Form 4a · Change of Undergraduate Thesis Adviser'
              : 'Form 4b · Change of Undergraduate Thesis Title',
          filename: '${adviser ? 'Form4a' : 'Form4b'}-$thesisId.pdf',
          buildPdf: () => buildChangeRequestPdf(request),
        ),
        // The copy the leader sent with the request, if any.
        ViewAttachedCopyButton(
          thesisId: thesisId,
          formId: adviser ? 'form4a' : 'form4b',
        ),
      ],
    );
  }
}
