import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

FacultyDirectoryEntry entry(String uid, String name, String role) =>
    FacultyDirectoryEntry(uid: uid, fullName: name, role: role);

void main() {
  late FakeFirebaseFirestore db;
  late ThesisRepository repo;
  late String thesisId;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
    thesisId = await repo.createThesis(
      leaderUid: 'leader-1', workingTitle: 'T', memberNames: const [],
      college: 'CICT', program: 'BSIT', semester: 'First',
      academicYear: '2026-2027',
    );
  });

  Future<void> submit() => repo.submitNominations(
        thesisId: thesisId,
        adviser: entry('a1', 'Dr. Armada', 'faculty'),
        panelists: [
          entry('p1', 'Dr. Diamante', 'faculty'),
          entry('p2', 'Prof. Padojinog', 'faculty'),
          entry('p3', 'Dr. Braganza', 'faculty'),
        ],
        exOfficio: [
          entry('c1', 'Dr. Bito-onon', 'coordinator'),
          entry('d1', 'Dr. Siason', 'dean'),
        ],
      );

  test('writes one nomination per person', () async {
    await submit();
    final noms = await repo.watchNominations(thesisId).first;
    expect(noms, hasLength(6));
  });

  test('nominated members are pending, ex officio are not', () async {
    await submit();
    final noms = await repo.watchNominations(thesisId).first;

    final adviser = noms.firstWhere((n) => n.nomineeUid == 'a1');
    expect(adviser.position, NominationPosition.adviser);
    expect(adviser.conformeStatus, ConformeStatus.pending);
    expect(adviser.exOfficio, isFalse);

    final dean = noms.firstWhere((n) => n.nomineeUid == 'd1');
    expect(dean.position, NominationPosition.dean);
    expect(dean.conformeStatus, ConformeStatus.exOfficio);
    expect(dean.exOfficio, isTrue);
    expect(dean.needsConforme, isFalse);

    final coordinator = noms.firstWhere((n) => n.nomineeUid == 'c1');
    expect(coordinator.position, NominationPosition.coordinator);
    expect(coordinator.conformeStatus, ConformeStatus.exOfficio);
    expect(coordinator.exOfficio, isTrue);
    expect(coordinator.needsConforme, isFalse);
  });

  test('advances the thesis to pending conforme', () async {
    await submit();
    final thesis = await repo.watchThesis(thesisId).first;
    expect(thesis!.status, ThesisStatus.nominationPendingConforme);
  });

  test('rejects fewer than three panel members', () async {
    expect(
      () => repo.submitNominations(
        thesisId: thesisId,
        adviser: entry('a1', 'Dr. Armada', 'faculty'),
        panelists: [entry('p1', 'Dr. Diamante', 'faculty')],
        exOfficio: const [],
      ),
      throwsArgumentError,
    );
  });

  test('adviser nomination wins when it collides with an ex-officio seat',
      () async {
    // The dean (uid 'd1') is nominated as adviser "for the sake of records".
    // Adviser must win: they are asked to accept and printed as Thesis
    // Adviser on Form 1, distinct from their ex-officio panel seat.
    await repo.submitNominations(
      thesisId: thesisId,
      adviser: entry('d1', 'Dr. Siason', 'dean'),
      panelists: [
        entry('p1', 'Dr. Diamante', 'faculty'),
        entry('p2', 'Prof. Padojinog', 'faculty'),
        entry('p3', 'Dr. Braganza', 'faculty'),
      ],
      exOfficio: [entry('d1', 'Dr. Siason', 'dean')],
    );

    final noms = await repo.watchNominations(thesisId).first;
    // 4 distinct people total (d1, p1, p2, p3) — catches a collision that
    // writes two separate documents (e.g. under different doc ids) instead
    // of resolving to one, which a same-uid count alone would miss.
    expect(noms, hasLength(4));
    expect(noms.where((n) => n.nomineeUid == 'd1'), hasLength(1));

    final dean = noms.firstWhere((n) => n.nomineeUid == 'd1');
    expect(dean.position, NominationPosition.adviser);
    expect(dean.exOfficio, isFalse);
    expect(dean.conformeStatus, ConformeStatus.pending);
    expect(dean.needsConforme, isTrue);
  });

  test('panelist nomination collapses into a single ex-officio entry',
      () async {
    // The coordinator (uid 'c1') is also named as a panelist "for the sake
    // of records". Ex officio wins over panelist: one document, not two,
    // and no Conforme is asked.
    await repo.submitNominations(
      thesisId: thesisId,
      adviser: entry('a1', 'Dr. Armada', 'faculty'),
      panelists: [
        entry('c1', 'Dr. Bito-onon', 'coordinator'),
        entry('p2', 'Prof. Padojinog', 'faculty'),
        entry('p3', 'Dr. Braganza', 'faculty'),
      ],
      exOfficio: [entry('c1', 'Dr. Bito-onon', 'coordinator')],
    );

    final noms = await repo.watchNominations(thesisId).first;
    // 4 distinct people total (a1, c1, p2, p3) — catches a collision that
    // writes two separate documents (e.g. under different doc ids) instead
    // of resolving to one, which a same-uid count alone would miss.
    expect(noms, hasLength(4));
    expect(noms.where((n) => n.nomineeUid == 'c1'), hasLength(1));

    final coordinator = noms.firstWhere((n) => n.nomineeUid == 'c1');
    expect(coordinator.position, NominationPosition.coordinator);
    expect(coordinator.exOfficio, isTrue);
    expect(coordinator.conformeStatus, ConformeStatus.exOfficio);
    expect(coordinator.needsConforme, isFalse);
  });
}
