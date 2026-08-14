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
  late String id;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
    id = await repo.createThesis(
      leaderUid: 'leader-1', workingTitle: 'T', memberNames: const [],
      college: 'CICT', program: 'BSIT', semester: 'First',
      academicYear: '2026-2027',
    );
    await repo.submitNominations(
      thesisId: id,
      adviser: entry('a1', 'Dr. Armada', 'faculty'),
      panelists: [
        entry('p1', 'Dr. Diamante', 'faculty'),
        entry('p2', 'Prof. Padojinog', 'faculty'),
        entry('p3', 'Dr. Braganza', 'faculty'),
      ],
      exOfficio: [entry('d1', 'Dr. Siason', 'dean')],
    );
  });

  Future<void> acceptAll() async {
    for (final uid in ['a1', 'p1', 'p2', 'p3']) {
      await repo.respondToNomination(
          thesisId: id, nomineeUid: uid, accept: true);
    }
  }

  test('accepting all non-ex-officio advances to pending coordinator',
      () async {
    await acceptAll();
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingCoordinator);
  });

  test('the ex officio dean never blocks the advance', () async {
    await acceptAll();
    final noms = await repo.watchNominations(id).first;
    final dean = noms.firstWhere((n) => n.nomineeUid == 'd1');
    expect(dean.conformeStatus, ConformeStatus.exOfficio);
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingCoordinator);
  });

  test(
      'a thesis whose ONLY unresponded nominations are ex officio still '
      'advances (regression for the ex-officio trap)', () async {
    // Accept every non-ex-officio nominee but deliberately leave the
    // ex-officio dean untouched (they are never asked). If the advance
    // logic ever gates on raw "all nominations accepted" instead of
    // needsConforme, this thesis will incorrectly stall in
    // nominationPendingConforme forever.
    await repo.respondToNomination(thesisId: id, nomineeUid: 'a1', accept: true);
    await repo.respondToNomination(thesisId: id, nomineeUid: 'p1', accept: true);
    await repo.respondToNomination(thesisId: id, nomineeUid: 'p2', accept: true);
    await repo.respondToNomination(thesisId: id, nomineeUid: 'p3', accept: true);

    final noms = await repo.watchNominations(id).first;
    final dean = noms.firstWhere((n) => n.nomineeUid == 'd1');
    // The dean was never touched — still sitting at exOfficio, not accepted.
    expect(dean.conformeStatus, ConformeStatus.exOfficio);

    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingCoordinator);
  });

  test('a partial set does not advance', () async {
    await repo.respondToNomination(
        thesisId: id, nomineeUid: 'a1', accept: true);
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingConforme);
  });

  test(
      'a single unresponded non-ex-officio nominee blocks the advance even '
      'when every other nominee (including ex officio) has settled',
      () async {
    // Accept everyone except p3. If the implementation only checked "is
    // there at least one accepted nomination" or otherwise mis-scoped the
    // outstanding check, this would wrongly advance.
    await repo.respondToNomination(thesisId: id, nomineeUid: 'a1', accept: true);
    await repo.respondToNomination(thesisId: id, nomineeUid: 'p1', accept: true);
    await repo.respondToNomination(thesisId: id, nomineeUid: 'p2', accept: true);

    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingConforme);
  });

  test('declining records the reason and does not advance', () async {
    await repo.respondToNomination(
        thesisId: id, nomineeUid: 'p1', accept: false,
        declineReason: 'Already at capacity');
    final noms = await repo.watchNominations(id).first;
    final p1 = noms.firstWhere((n) => n.nomineeUid == 'p1');
    expect(p1.conformeStatus, ConformeStatus.declined);
    expect(p1.declineReason, 'Already at capacity');
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingConforme);
  });

  test('recommend records who acted and advances to pending dean', () async {
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingDean);
    expect(thesis.coordinatorRecommendedBy, 'c1');
    expect(thesis.coordinatorRecommendedAt, isNotNull);
  });

  test('approve fixes the panel from accepted nominations', () async {
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    await repo.approve(thesisId: id, deanUid: 'd1');

    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationApproved);
    expect(thesis.adviserUid, 'a1');
    expect(thesis.panelistUids.toSet(), {'p1', 'p2', 'p3'});
    expect(thesis.deanApprovedBy, 'd1');
  });

  test('the ex officio dean is absent from panelistUids after approval',
      () async {
    // d1 is ex officio AND is the one calling approve() as dean — a naive
    // filter keyed only on "accepted" (the dean's ConformeStatus is
    // exOfficio, not accepted, so this should already exclude them, but we
    // assert it explicitly since panelistUids[] is untested territory).
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    await repo.approve(thesisId: id, deanUid: 'd1');

    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.panelistUids.contains('d1'), isFalse);
  });

  test(
      'an ex-officio nomination is excluded from panelistUids even when its '
      'position is panelist and its status is accepted', () async {
    // submitNominations() never actually produces exOfficio:true combined
    // with position:panelist (an ex-officio collision always relabels
    // position to dean/coordinator), so the test above cannot by itself
    // prove the `!n.exOfficio` guard inside approve() is doing anything —
    // the position filter alone would already exclude the dean. Write a
    // nomination directly to decouple the two fields and prove the guard
    // is load-bearing independent of that invariant.
    await db
        .collection('theses')
        .doc(id)
        .collection('nominations')
        .doc('c-extra')
        .set({
      'nomineeName': 'Coordinator Extra',
      'position': 'panelist',
      'exOfficio': true,
      'conformeStatus': 'accepted',
      'respondedAt': null,
      'declineReason': null,
    });

    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    await repo.approve(thesisId: id, deanUid: 'd1');

    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.panelistUids.contains('c-extra'), isFalse);
    expect(thesis.panelistUids.toSet(), {'p1', 'p2', 'p3'});
  });

  test(
      'the adviser uid is absent from panelistUids and present in '
      'adviserUid, even though the adviser nomination is also "accepted"',
      () async {
    // a1 shares ConformeStatus.accepted with the panelists after acceptAll,
    // so a filter that keys only on conformeStatus == accepted (and forgets
    // to check position/exOfficio) would wrongly fold the adviser into the
    // panel list too.
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    await repo.approve(thesisId: id, deanUid: 'd1');

    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.adviserUid, 'a1');
    expect(thesis.panelistUids.contains('a1'), isFalse);
  });

  test('a declined panelist is absent from panelistUids after approval',
      () async {
    // A decline permanently blocks respondToNomination's own advance (see
    // report: the brief specifies no re-nomination/replacement path, so a
    // decline leaves a needsConforme nomination that can never become
    // accepted). To keep at least three accepted panelists despite one
    // decline, this thesis has four panel nominees. To isolate and prove
    // the panelistUids[] filter itself excludes decliners (independent of
    // that gap), we record the responses via the repository and then drive
    // the thesis status forward directly, exactly as a future "replace a
    // decliner" flow would need to.
    final id2 = await repo.createThesis(
      leaderUid: 'leader-2', workingTitle: 'T2', memberNames: const [],
      college: 'CICT', program: 'BSIT', semester: 'First',
      academicYear: '2026-2027',
    );
    await repo.submitNominations(
      thesisId: id2,
      adviser: entry('a1', 'Dr. Armada', 'faculty'),
      panelists: [
        entry('p1', 'Dr. Diamante', 'faculty'),
        entry('p2', 'Prof. Padojinog', 'faculty'),
        entry('p3', 'Dr. Braganza', 'faculty'),
        entry('p4', 'Dr. Cruz', 'faculty'),
      ],
      exOfficio: [entry('d1', 'Dr. Siason', 'dean')],
    );

    await repo.respondToNomination(
        thesisId: id2, nomineeUid: 'a1', accept: true);
    await repo.respondToNomination(
        thesisId: id2, nomineeUid: 'p1', accept: false,
        declineReason: 'Conflict of interest');
    await repo.respondToNomination(
        thesisId: id2, nomineeUid: 'p2', accept: true);
    await repo.respondToNomination(
        thesisId: id2, nomineeUid: 'p3', accept: true);
    await repo.respondToNomination(
        thesisId: id2, nomineeUid: 'p4', accept: true);

    final mid = await repo.watchThesis(id2).first;
    expect(mid!.status, ThesisStatus.nominationPendingConforme,
        reason: 'documents the gap: a decline blocks the advance with no '
            'specified way forward');

    await db.collection('theses').doc(id2).update(
        {'status': ThesisStatus.nominationPendingDean.value});
    await repo.approve(thesisId: id2, deanUid: 'd1');

    final thesis = await repo.watchThesis(id2).first;
    expect(thesis!.panelistUids.contains('p1'), isFalse);
    expect(thesis.panelistUids.toSet(), {'p2', 'p3', 'p4'});
  });

  test('the faculty inbox finds a nomination across theses with its thesisId',
      () async {
    final pending = await repo.watchMyPendingNominations('p1').first;
    expect(pending, hasLength(1));
    expect(pending.first.thesisId, id);
    expect(pending.first.nomination.nomineeUid, 'p1');
  });

  test('the faculty inbox drops a nomination once it is no longer pending',
      () async {
    await repo.respondToNomination(
        thesisId: id, nomineeUid: 'p1', accept: true);
    final pending = await repo.watchMyPendingNominations('p1').first;
    expect(pending, isEmpty);
  });
}
