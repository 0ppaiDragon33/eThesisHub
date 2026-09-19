import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

import '../../support/fake_firestore_settle.dart';

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

  test('stamps nominationsSubmittedAt in the same write as the status flip',
      () async {
    final before = await repo.watchThesis(thesisId).first;
    expect(before!.nominationsSubmittedAt, isNull);

    await submit();

    final after = await repo.watchThesis(thesisId).first;
    expect(after!.nominationsSubmittedAt, isNotNull);
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
    //
    // FOUR panelists are passed, not three, and that is load-bearing rather
    // than incidental: the collision means only THREE of them survive as real
    // panel members, and `submitNominations` now refuses any submission whose
    // effective panel would fall below three (I2 — such a thesis wedges
    // permanently at `approve`). This fixture used to pass three, one of them
    // the coordinator, which is precisely the wedging shape; the subject
    // under test here is the collapse itself, so the fixture is widened to a
    // submission that is legal rather than the assertions being weakened.
    await repo.submitNominations(
      thesisId: thesisId,
      adviser: entry('a1', 'Dr. Armada', 'faculty'),
      panelists: [
        entry('c1', 'Dr. Bito-onon', 'coordinator'),
        entry('p2', 'Prof. Padojinog', 'faculty'),
        entry('p3', 'Dr. Braganza', 'faculty'),
        entry('p4', 'Dr. Diamante', 'faculty'),
      ],
      exOfficio: [entry('c1', 'Dr. Bito-onon', 'coordinator')],
    );

    final noms = await repo.watchNominations(thesisId).first;
    // 5 distinct people total (a1, c1, p2, p3, p4) — catches a collision that
    // writes two separate documents (e.g. under different doc ids) instead
    // of resolving to one, which a same-uid count alone would miss.
    expect(noms, hasLength(5));
    expect(noms.where((n) => n.nomineeUid == 'c1'), hasLength(1));

    final coordinator = noms.firstWhere((n) => n.nomineeUid == 'c1');
    expect(coordinator.position, NominationPosition.coordinator);
    expect(coordinator.exOfficio, isTrue);
    expect(coordinator.conformeStatus, ConformeStatus.exOfficio);
    expect(coordinator.needsConforme, isFalse);
  });

  // ---- Stalled-thesis recovery -----------------------------------------
  //
  // A declined Conforme used to be terminal: the nominee cannot un-decline,
  // respondToNomination counts them outstanding forever, and the rules
  // freeze the leader out the moment the thesis leaves 'draft'. Recovery was
  // the Firebase Console.

  test('reopening a stalled thesis returns it to draft', () async {
    await submit();
    await repo.respondToNomination(
      thesisId: thesisId,
      nomineeUid: 'p1',
      accept: false,
      declineReason: 'On sabbatical.',
    );

    await repo.reopenForRenomination(
      thesisId: thesisId,
      coordinatorUid: 'c1',
    );

    await settleFakeTransaction();

    final thesis = await repo.watchThesis(thesisId).first;
    expect(thesis!.status, ThesisStatus.draft);
  });

  test('reopening refuses a thesis that is not awaiting Conforme', () async {
    // Still 'draft' -- never submitted. The same guard is what stops a
    // reopen rewinding an already-recommended or already-approved thesis.
    expect(
      () => repo.reopenForRenomination(
        thesisId: thesisId,
        coordinatorUid: 'c1',
      ),
      throwsStateError,
    );
  });

  // This used to assert the opposite — that resubmitting silently pruned ANY
  // nominee dropped from the roster, including one still waiting to answer.
  // That passed only because `fake_cloud_firestore` does not evaluate rules.
  // Firestore does: the leader's delete arm is pinned to
  // `resource.data.conformeStatus == 'declined'`, so removing a pending or
  // accepted seat is refused, and the whole batch fails with a bare
  // permission-denied that the nominate screen then blamed on the nominees'
  // availability. Reopening is for replacing a REFUSAL, not for reshuffling
  // a panel that is still answering.
  test('resubmitting will not drop a nominee who has not declined', () async {
    await submit();
    await repo.reopenForRenomination(
      thesisId: thesisId,
      coordinatorUid: 'c1',
    );

    // p1 is still pending — nobody declined here — and is dropped for p4.
    await expectLater(
      repo.submitNominations(
        thesisId: thesisId,
        adviser: entry('a1', 'Dr. Armada', 'faculty'),
        panelists: [
          entry('p4', 'Dr. Nuevo', 'faculty'),
          entry('p2', 'Prof. Padojinog', 'faculty'),
          entry('p3', 'Dr. Braganza', 'faculty'),
        ],
        exOfficio: [
          entry('c1', 'Dr. Bito-onon', 'coordinator'),
          entry('d1', 'Dr. Siason', 'dean'),
        ],
      ),
      throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
          'message', contains('has not answered yet'))),
    );

    // And nothing was half-written: the roster is exactly as it was.
    final noms = await repo.watchNominations(thesisId).first;
    expect(noms.where((n) => n.nomineeUid == 'p1'), hasLength(1));
    expect(noms.where((n) => n.nomineeUid == 'p4'), isEmpty);
  });

  // The regression that matters: the whole rescue path, end to end. Without
  // the prune this fails at the last line -- p1's `declined` document
  // survives their replacement and counts as outstanding forever, so the
  // thesis stalls again on the very action meant to free it.
  test('decline, reopen, re-nominate and accept advances the thesis',
      () async {
    await submit();
    await repo.respondToNomination(
      thesisId: thesisId,
      nomineeUid: 'p1',
      accept: false,
      declineReason: 'On sabbatical.',
    );
    await repo.reopenForRenomination(
      thesisId: thesisId,
      coordinatorUid: 'c1',
    );

    await repo.submitNominations(
      thesisId: thesisId,
      adviser: entry('a1', 'Dr. Armada', 'faculty'),
      panelists: [
        entry('p4', 'Dr. Nuevo', 'faculty'),
        entry('p2', 'Prof. Padojinog', 'faculty'),
        entry('p3', 'Dr. Braganza', 'faculty'),
      ],
      exOfficio: [
        entry('c1', 'Dr. Bito-onon', 'coordinator'),
        entry('d1', 'Dr. Siason', 'dean'),
      ],
    );

    for (final uid in ['a1', 'p2', 'p3', 'p4']) {
      await repo.respondToNomination(
        thesisId: thesisId,
        nomineeUid: uid,
        accept: true,
      );
    }

    await settleFakeTransaction();

    final thesis = await repo.watchThesis(thesisId).first;
    expect(thesis!.status, ThesisStatus.nominationPendingCoordinator);
  });
}
