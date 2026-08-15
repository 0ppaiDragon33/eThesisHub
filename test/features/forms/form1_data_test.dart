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

    final deanRow =
        data.conformeRows.firstWhere((r) => r.name == 'Dr. Siason');
    expect(deanRow.status, 'Ex officio member');
    expect(deanRow.role, contains('ex officio'));
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

  test('ex officio entries come after nominated members in conformeRows order', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    final names = data.conformeRows.map((r) => r.name).toList();
    final exOfficioNames = {'Dr. Bito-onon', 'Dr. Siason'};
    final firstExOfficioIndex =
        names.indexWhere((n) => exOfficioNames.contains(n));
    final lastNominatedIndex =
        names.lastIndexWhere((n) => !exOfficioNames.contains(n));
    expect(firstExOfficioIndex, greaterThan(lastNominatedIndex));
  });
}
