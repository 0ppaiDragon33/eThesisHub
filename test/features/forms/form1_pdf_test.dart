import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/form1_data.dart';
import 'package:ethesishub/features/forms/form1_pdf.dart';

/// The `pdf` package is a generator, not a parser — there is no
/// `PdfDocument.load`/text-extraction API in `pdf` or `printing`. What makes
/// text assertions possible at all is that `buildForm1Pdf` builds its
/// `pw.Document` with `compress: false`, so the content stream's `Tj`/`TJ`
/// text-showing operators are plain bytes rather than Flate-compressed ones.
/// This pulls every parenthesized literal string out of those operators, in
/// document order, and joins them with a space — a real (if crude) text
/// extraction, not a re-assertion of the smoke test.
String _extractText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final literal = RegExp(r'\(((?:\\.|[^()\\])*)\)');
  final buffer = StringBuffer();
  for (final match in literal.allMatches(raw)) {
    buffer.write(match.group(1));
    buffer.write(' ');
  }
  return buffer.toString();
}

void main() {
  Thesis buildThesis({
    String? coordinatorRecommendedBy,
    String? deanApprovedBy,
    List<String> memberNames = const ['Bagsain, Karlo June'],
  }) =>
      Thesis(
        id: 't1', leaderUid: 'l1', memberNames: memberNames,
        workingTitle: 'eThesisHub', college: 'CICT', program: 'BSIT',
        semester: 'First', academicYear: '2026-2027',
        status: ThesisStatus.nominationApproved,
        panelistUids: const ['p1', 'p2', 'p3'],
        createdAt: DateTime.utc(2026, 8, 14), adviserUid: 'a1',
        coordinatorRecommendedBy: coordinatorRecommendedBy,
        deanApprovedBy: deanApprovedBy,
      );

  final acceptedNominations = [
    Nomination(
        nomineeUid: 'a1', nomineeName: 'Dr. Armada',
        position: NominationPosition.adviser, exOfficio: false,
        conformeStatus: ConformeStatus.accepted,
        respondedAt: DateTime.utc(2026, 8, 14, 10, 22)),
    for (final p in ['p1', 'p2', 'p3'])
      Nomination(
          nomineeUid: p, nomineeName: 'Dr. $p',
          position: NominationPosition.panelist, exOfficio: false,
          conformeStatus: ConformeStatus.accepted,
          respondedAt: DateTime.utc(2026, 8, 14, 11, 0)),
    Nomination(
        nomineeUid: 'd1', nomineeName: 'Dr. Siason',
        position: NominationPosition.dean, exOfficio: true,
        conformeStatus: ConformeStatus.exOfficio),
  ];

  test('produces a non-empty PDF', () async {
    final data = Form1Data.assemble(
      thesis: buildThesis(),
      nominations: acceptedNominations,
      leaderName: 'Karl Joshua P. Vargas',
      directoryNames: const {},
    );

    final bytes = await buildForm1Pdf(data);
    expect(bytes.length, greaterThan(1000));
    // Every PDF starts with %PDF.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test(
      'extracted text carries the adviser, the ex officio marker, and orders '
      'ex officio after the nominated members', () async {
    final data = Form1Data.assemble(
      thesis: buildThesis(
          coordinatorRecommendedBy: 'c1', deanApprovedBy: 'd1'),
      nominations: [
        ...acceptedNominations,
        Nomination(
            nomineeUid: 'c1', nomineeName: 'Dr. Bito-onon',
            position: NominationPosition.coordinator, exOfficio: true,
            conformeStatus: ConformeStatus.exOfficio),
      ],
      leaderName: 'Karl Joshua P. Vargas',
      directoryNames: const {'c1': 'Dr. Bito-onon', 'd1': 'Dr. Siason'},
    );

    final bytes = await buildForm1Pdf(data);
    final text = _extractText(bytes);

    // Adviser and panel names appear (uppercased, per the brief's layout).
    expect(text, contains('ARMADA'));
    expect(text, contains('DR. P1'));
    // The leader is printed and marked as leader.
    expect(text, contains('KARL JOSHUA P. VARGAS'));
    expect(text, contains('Group Leader'));
    // Plural wording, since this thesis has a member beyond the leader.
    expect(text, contains('We'));
    expect(text, contains('have the honor'));
    // Ex officio entries carry the marker text in place of an acceptance
    // timestamp — proving they are not rendered as though they accepted.
    expect(text, contains('Ex officio member'));
    // The adviser's Conforme row (a nominated member) must render before the
    // ex officio marker text: ex officio comes after nominated members.
    final adviserIndex = text.indexOf('Armada');
    final exOfficioIndex = text.indexOf('Ex officio member');
    expect(adviserIndex, greaterThanOrEqualTo(0));
    expect(exOfficioIndex, greaterThan(adviserIndex));
  });

  test('a solo thesis reads in the singular, not the plural', () async {
    final soloThesis = buildThesis(memberNames: const []);
    final data = Form1Data.assemble(
      thesis: soloThesis,
      nominations: [
        Nomination(
            nomineeUid: 'a1', nomineeName: 'Dr. Armada',
            position: NominationPosition.adviser, exOfficio: false,
            conformeStatus: ConformeStatus.accepted,
            respondedAt: DateTime.utc(2026, 8, 14, 10, 22)),
      ],
      leaderName: 'Karl',
      directoryNames: const {},
    );

    final bytes = await buildForm1Pdf(data);
    final text = _extractText(bytes);

    expect(text, contains('I have the honor'));
    expect(text, isNot(contains('We have the honor')));
  });
}
