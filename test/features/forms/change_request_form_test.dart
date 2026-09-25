import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/change_request_form.dart';

import 'pdf_text.dart';

Thesis _thesis({required String workingTitle}) => Thesis(
  id: 'thesis-1',
  leaderUid: 'leader-1',
  memberNames: const ['Karl Joshua'],
  workingTitle: workingTitle,
  college: 'CICS',
  program: 'BSCS',
  semester: '1st',
  academicYear: '2026-2027',
  status: ThesisStatus.titleApproved,
  panelistUids: const [],
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  // The forms embed Source Serif 4 via rootBundle, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an adviser request fills Form 4a with the advisers and the reasons',
    () async {
      final request = ChangeRequest(
        type: ChangeRequestType.adviser,
        stage: ChangeRequestStage.approved,
        reasons: 'Workload realignment across the research team',
        leaderUid: 'leader-1',
        signoffs: const {},
        newAdviserName: 'Reginald Quimzon',
        formerAdviserName: 'Bartholomew Escaner',
      );
      final thesis = _thesis(workingTitle: 'Untouched Working Title');

      final text = extractPdfText(
        await buildChangeRequestPdf(request, thesis: thesis),
      );

      expect(text, contains('Reginald'));
      expect(text, contains('Escaner'));
      expect(text, contains('Workload realignment across the research team'));
    },
  );

  test('a title request fills Form 4b with the old title, new title and '
      'reasons', () async {
    final request = ChangeRequest(
      type: ChangeRequestType.title,
      stage: ChangeRequestStage.approved,
      reasons: 'Scope narrowed after the title defence panel feedback',
      leaderUid: 'leader-1',
      signoffs: const {},
      newTitle: 'A Framework for Zylotropic Inference Systems',
    );
    final thesis = _thesis(workingTitle: 'The Original Zorquinelle Study');

    final text = extractPdfText(
      await buildChangeRequestPdf(request, thesis: thesis),
    );

    expect(text, contains('Zorquinelle'));
    expect(text, contains('Zylotropic'));
    expect(
      text,
      contains('Scope narrowed after the title defence panel feedback'),
    );
  });
}
