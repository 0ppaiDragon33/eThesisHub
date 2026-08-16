import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/form1_data.dart';

Nomination nom(String uid, String name, NominationPosition pos,
        {bool ex = false, ConformeStatus status = ConformeStatus.accepted}) =>
    Nomination(
      nomineeUid: uid, nomineeName: name, position: pos,
      exOfficio: ex, conformeStatus: status,
      respondedAt: DateTime.utc(2026, 8, 14, 10, 22),
    );

void main() {
  final thesis = Thesis(
    id: 't1', leaderUid: 'l1', memberNames: const ['Bagsain, Karlo June'],
    workingTitle: 'eThesisHub', college: 'CICT', program: 'BSIT',
    semester: 'First', academicYear: '2026-2027',
    status: ThesisStatus.nominationApproved, panelistUids: const ['p1'],
    createdAt: DateTime.utc(2026, 8, 14), adviserUid: 'a1',
    coordinatorRecommendedBy: 'c1', deanApprovedBy: 'd1',
  );

  final nominations = [
    nom('a1', 'Dr. Armada', NominationPosition.adviser),
    nom('p1', 'Dr. Diamante', NominationPosition.panelist),
    nom('c1', 'Dr. Bito-onon', NominationPosition.coordinator,
        ex: true, status: ConformeStatus.exOfficio),
    nom('d1', 'Dr. Siason', NominationPosition.dean,
        ex: true, status: ConformeStatus.exOfficio),
  ];

  test('separates nominated members from ex officio', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );
    expect(data.adviserName, 'Dr. Armada');
    expect(data.panelNames, ['Dr. Diamante']);
    expect(data.exOfficioEntries.map((e) => e.name).toSet(),
        {'Dr. Bito-onon', 'Dr. Siason'});
  });

  test('conforme rows carry acceptance text for nominated members only', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );
    final adviserRow =
        data.conformeRows.firstWhere((r) => r.name == 'Dr. Armada');
    expect(adviserRow.status, contains('Accepted'));
  });

  test('an ex officio member who signs below is not also listed above', () {
    // The Coordinator who recommends and the Dean who approves each get
    // their own signature block. Printing them again as "Ex officio member"
    // in the Conforme list repeated what those blocks already say, and cost
    // four lines — which is what pushed a six-researcher form off the sheet.
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );

    final names = data.conformeRows.map((r) => r.name);
    expect(names, isNot(contains('Dr. Bito-onon')),
        reason: 'she signs Recommending Approval below');
    expect(names, isNot(contains('Dr. Siason')),
        reason: 'he signs Approved below');
    // The signature blocks still name them.
    expect(data.coordinatorName, 'Dr. Bito-onon');
    expect(data.deanName, 'Dr. Siason');
  });

  test('an ex officio member who signs nowhere is still listed', () {
    // A college can have more than one coordinator and only one of them
    // recommends. The others sign nowhere on the form, so this row is the
    // only record that they sit on the panel — dropping every ex officio
    // row wholesale would erase them.
    final data = Form1Data.assemble(
      thesis: thesis,
      nominations: [
        ...nominations,
        nom('c2', 'Dr. Zamora', NominationPosition.coordinator,
            ex: true, status: ConformeStatus.exOfficio),
      ],
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );

    final zamora =
        data.conformeRows.firstWhere((r) => r.name == 'Dr. Zamora');
    expect(zamora.status, 'Ex officio member');
    expect(zamora.role, contains('ex officio'));
  });

  test('all researchers are listed with the leader first', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );
    expect(data.researchers.first.name, 'Karl Joshua P. Vargas');
    expect(data.researchers.first.isLeader, isTrue);
    expect(data.researchers, hasLength(2));
  });

  test('uses plural wording when the group has members', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.subjectPronoun, 'We');
    expect(data.possessivePronoun, 'our');
  });

  test('uses singular wording for a solo thesis', () {
    final solo = Thesis(
      id: 't2', leaderUid: 'l1', memberNames: const [],
      workingTitle: 'X', college: 'CICT', program: 'BSIT',
      semester: 'First', academicYear: '2026-2027',
      status: ThesisStatus.nominationApproved, panelistUids: const [],
      createdAt: DateTime.utc(2026, 8, 14),
    );
    final data = Form1Data.assemble(
      thesis: solo, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.subjectPronoun, 'I');
    expect(data.possessivePronoun, 'my');
  });

  test('a dean nominated by name as adviser lands in the adviser slot, not ex officio', () {
    final deanAsAdviser = [
      nom('d1', 'Dean Reyes', NominationPosition.adviser,
          ex: false, status: ConformeStatus.accepted),
    ];
    final data = Form1Data.assemble(
      thesis: thesis, nominations: deanAsAdviser,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.adviserName, 'Dean Reyes');
    expect(data.exOfficioEntries, isEmpty);
    final adviserRow =
        data.conformeRows.firstWhere((r) => r.name == 'Dean Reyes');
    expect(adviserRow.status, contains('Accepted'));
    expect(adviserRow.status, isNot('Ex officio member'));
  });

  test('submittedOn is the nomination submission date, not the creation date',
      () {
    // Deliberately distinct from createdAt: if the two were equal, a bug
    // that reads `createdAt` instead of `nominationsSubmittedAt` would still
    // pass this assertion. That correlated-fixture trap has bitten this
    // branch before.
    final withSubmission = Thesis(
      id: 't3', leaderUid: 'l1', memberNames: const [],
      workingTitle: 'X', college: 'CICT', program: 'BSIT',
      semester: 'First', academicYear: '2026-2027',
      status: ThesisStatus.nominationApproved, panelistUids: const [],
      createdAt: DateTime.utc(2026, 6, 1),
      nominationsSubmittedAt: DateTime.utc(2026, 8, 14, 10, 22),
    );
    final data = Form1Data.assemble(
      thesis: withSubmission, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.submittedOn, DateTime.utc(2026, 8, 14, 10, 22));
    expect(data.submittedOn, isNot(withSubmission.createdAt));
  });

  test('submittedOn falls back to createdAt when nominationsSubmittedAt is '
      'null (a thesis predating the field)', () {
    final legacy = Thesis(
      id: 't4', leaderUid: 'l1', memberNames: const [],
      workingTitle: 'X', college: 'CICT', program: 'BSIT',
      semester: 'First', academicYear: '2026-2027',
      status: ThesisStatus.nominationApproved, panelistUids: const [],
      createdAt: DateTime.utc(2026, 6, 1),
    );
    final data = Form1Data.assemble(
      thesis: legacy, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.submittedOn, DateTime.utc(2026, 6, 1));
  });

  // --- the signatory names Form 1 prints for the Dean -------------------
  //
  // `directoryNames` was passed `const {}` by the only production caller, so
  // this branch was dead and both names rested entirely on the ex-officio
  // fallback. `ThesisStatusScreen._download` now resolves the two uids
  // against the live faculty directory, which is what these three pin down.

  test('the ex-officio fallback names the coordinator and dean when the '
      'directory has nothing to add', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.coordinatorName, 'Dr. Bito-onon');
    expect(data.deanName, 'Dr. Siason');
  });

  test('a coordinator who holds NO ex-officio seat on this thesis prints '
      'blank without the directory, and correctly with it', () {
    // The case the wiring exists for: a coordinator promoted (or first signed
    // in) AFTER this thesis's roster was fixed has no seat on it, and the
    // roster can never be amended — creates are pinned to `draft`.
    final recommendedByOutsider = Thesis(
      id: 't5', leaderUid: 'l1', memberNames: const [],
      workingTitle: 'X', college: 'CICT', program: 'BSIT',
      semester: 'First', academicYear: '2026-2027',
      status: ThesisStatus.nominationApproved, panelistUids: const ['p1'],
      createdAt: DateTime.utc(2026, 8, 14), adviserUid: 'a1',
      coordinatorRecommendedBy: 'c-new', deanApprovedBy: 'd1',
    );

    final withoutDirectory = Form1Data.assemble(
      thesis: recommendedByOutsider, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(withoutDirectory.coordinatorName, isNull,
        reason: 'this is the blank name on the printed form');

    final withDirectory = Form1Data.assemble(
      thesis: recommendedByOutsider, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {'c-new': 'Dr. Nuevo'},
    );
    expect(withDirectory.coordinatorName, 'Dr. Nuevo');
    expect(withDirectory.deanName, 'Dr. Siason',
        reason: 'the dean still resolves through the ex-officio fallback');
  });

  test('the directory name wins over the ex-officio nomination name', () {
    // A faculty member who has since changed their recorded name: the
    // directory is live, the nomination is a snapshot taken at submission.
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl',
      directoryNames: const {'c1': 'Dr. Bito-onon, PhD'},
    );
    expect(data.coordinatorName, 'Dr. Bito-onon, PhD');
  });

  test('ex officio entries come after nominated members in conformeRows order', () {
    // Ordered against a coordinator who signs nowhere: c1 and d1 both have
    // signature blocks below, so their ex-officio rows are deliberately not
    // printed and there would otherwise be nothing left to order.
    final data = Form1Data.assemble(
      thesis: thesis,
      nominations: [
        ...nominations,
        nom('c2', 'Dr. Zamora', NominationPosition.coordinator,
            ex: true, status: ConformeStatus.exOfficio),
      ],
      leaderName: 'Karl', directoryNames: const {},
    );
    final names = data.conformeRows.map((r) => r.name).toList();
    const exOfficioNames = {'Dr. Zamora'};
    final firstExOfficioIndex =
        names.indexWhere((n) => exOfficioNames.contains(n));
    final lastNominatedIndex =
        names.lastIndexWhere((n) => !exOfficioNames.contains(n));
    expect(firstExOfficioIndex, greaterThan(lastNominatedIndex));
  });
}
