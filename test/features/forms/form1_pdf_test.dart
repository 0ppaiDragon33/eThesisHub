import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
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
    DateTime? createdAt,
    DateTime? nominationsSubmittedAt,
  }) =>
      Thesis(
        id: 't1', leaderUid: 'l1', memberNames: memberNames,
        workingTitle: 'eThesisHub', college: 'CICT', program: 'BSIT',
        semester: 'First', academicYear: '2026-2027',
        status: ThesisStatus.nominationApproved,
        panelistUids: const ['p1', 'p2', 'p3'],
        createdAt: createdAt ?? DateTime.utc(2026, 8, 14), adviserUid: 'a1',
        coordinatorRecommendedBy: coordinatorRecommendedBy,
        deanApprovedBy: deanApprovedBy,
        nominationsSubmittedAt: nominationsSubmittedAt,
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

  test(
      'the printed date is the nomination submission date, not the group '
      'creation date', () async {
    // createdAt and nominationsSubmittedAt are deliberately different
    // months, so a bug that prints `createdAt` (Finding 2's actual bug)
    // shows up as the wrong month in the extracted text, not merely a wrong
    // day on an otherwise-matching fixture.
    final data = Form1Data.assemble(
      thesis: buildThesis(
        createdAt: DateTime.utc(2026, 6, 1),
        nominationsSubmittedAt: DateTime.utc(2026, 8, 14),
      ),
      nominations: acceptedNominations,
      leaderName: 'Karl Joshua P. Vargas',
      directoryNames: const {},
    );

    final bytes = await buildForm1Pdf(data);
    final text = _extractText(bytes);

    expect(text, contains('14 August 2026'));
    expect(text, isNot(contains('1 June 2026')));
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

  // --- §7.3: "nominated names in bold" -------------------------------
  //
  // `_extractText` pulls literal strings out of `Tj`/`TJ` operators, but the
  // font-weight distinction between a Helvetica and a Helvetica-Bold glyph
  // run lives in the graphics-state operators around the text-showing ops,
  // not in the parenthesized string literals themselves — the extractor
  // cannot see it. `buildAdviserParagraphSpan` and `buildPanelParagraphSpan`
  // are exposed as standalone, non-rendering functions specifically so the
  // span tree can be asserted on directly instead: this inspects the actual
  // `pw.TextStyle` the widget tree carries, which is what `pdf` consults to
  // choose the font when the page is rendered.
  test('the adviser name in the body paragraph is bold; the rest is not',
      () {
    final data = Form1Data.assemble(
      thesis: buildThesis(),
      nominations: acceptedNominations,
      leaderName: 'Karl Joshua P. Vargas',
      directoryNames: const {},
    );

    final span = buildAdviserParagraphSpan(data);
    final children = span.children!.cast<pw.TextSpan>();

    final nameSpan =
        children.firstWhere((s) => s.text == data.adviserName.toUpperCase());
    expect(nameSpan.style?.fontWeight, pw.FontWeight.bold);

    final proseSpans = children.where((s) => s != nameSpan);
    expect(proseSpans, isNotEmpty);
    for (final s in proseSpans) {
      expect(s.style?.fontWeight, isNot(pw.FontWeight.bold));
    }
  });

  test('the panel names in the body paragraph are bold; the rest is not',
      () {
    final data = Form1Data.assemble(
      thesis: buildThesis(),
      nominations: acceptedNominations,
      leaderName: 'Karl Joshua P. Vargas',
      directoryNames: const {},
    );

    final span = buildPanelParagraphSpan(data);
    final children = span.children!.cast<pw.TextSpan>();

    final expectedPanelText = panelSentence(data.panelNames).toUpperCase();
    final nameSpan =
        children.firstWhere((s) => s.text == expectedPanelText);
    expect(nameSpan.style?.fontWeight, pw.FontWeight.bold);

    final proseSpans = children.where((s) => s != nameSpan);
    expect(proseSpans, isNotEmpty);
    for (final s in proseSpans) {
      expect(s.style?.fontWeight, isNot(pw.FontWeight.bold));
    }
  });

  test('a large group does not lose the approvals off the bottom', () async {
    // Found in a real submission. The form was a single `pw.Page`, which
    // CLIPS overflow silently — no exception, nothing in the logs. A group
    // of six researchers pushed the end of the document past the sheet, and
    // the generated PDF stopped mid-Conforme: the last panel member, both
    // ex-officio entries, the Coordinator's recommendation and the Dean's
    // approval were all absent from the form that goes to the Dean.
    //
    // Every existing test here uses a one-member group, which fits, so none
    // of them could see it.
    final data = Form1Data.assemble(
      thesis: buildThesis(
        memberNames: const [
          'Bagsain, Karlo June',
          'De los Reyes, Leonel',
          'Eredillas, Butch S.',
          'Solinap, Jepte',
          'Vargas, Karl Joshua',
        ],
        coordinatorRecommendedBy: 'c1',
        deanApprovedBy: 'd1',
      ),
      nominations: [
        ...acceptedNominations,
        Nomination(
            nomineeUid: 'c1', nomineeName: 'Dr. Bito-onon',
            position: NominationPosition.coordinator, exOfficio: true,
            conformeStatus: ConformeStatus.exOfficio),
      ],
      leaderName: 'Kira Yuuki',
      directoryNames: const {'c1': 'Dr. Bito-onon', 'd1': 'Dr. Siason'},
    );

    final text = _extractText(await buildForm1Pdf(data));

    // The last researcher must survive, and so must everything after them.
    expect(text, contains('VARGAS, KARL JOSHUA'));
    // Every nominee's Conforme row, including the third panel member.
    for (final p in ['Dr. p1', 'Dr. p2', 'Dr. p3']) {
      expect(text, contains(p), reason: '$p lost off the bottom of the form');
    }
    // The ex-officio entries, which print after the nominated members.
    expect(text, contains('Dr. Bito-onon'));
    expect(text, contains('Dr. Siason'));
    // And the two signature blocks the whole form exists to carry.
    expect(text, contains('Recommending Approval'));
    expect(text, contains('Approved'));
    // The footer is last, so its presence proves nothing was truncated.
    expect(text, contains('Academic Excellence'));
  });
}
