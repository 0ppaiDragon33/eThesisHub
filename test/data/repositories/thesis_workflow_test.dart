import 'dart:async' show unawaited;

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

  // --- Finding 1: respondToNomination must never walk status backwards ---

  test(
      'a response arriving after the thesis is already approved cannot walk '
      'it backwards (regression: reviewer-reported bug)', () async {
    // Reviewer's exact scenario: accept-all -> recommend -> approve -> one
    // more accept from a nominee who already accepted. Before the fix,
    // respondToNomination recomputed "outstanding is empty -> advance to
    // nominationPendingCoordinator" unconditionally on *every* call, with
    // no status guard at all, so this regressed an already-APPROVED thesis
    // back to nominationPendingCoordinator.
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    await repo.approve(thesisId: id, deanUid: 'd1');

    final approved = await repo.watchThesis(id).first;
    expect(approved!.status, ThesisStatus.nominationApproved);

    await expectLater(
      repo.respondToNomination(thesisId: id, nomineeUid: 'a1', accept: true),
      throwsA(isA<StateError>()),
    );

    final after = await repo.watchThesis(id).first;
    expect(after!.status, ThesisStatus.nominationApproved,
        reason: 'thesis status must never move backwards under any input');
  });

  test(
      'a response arriving after conforme review has closed but before '
      'approval is rejected, not silently recorded', () async {
    // Same guard, checked from the other open transition: once every
    // nominee has settled and the thesis has moved to
    // nominationPendingCoordinator, a late/duplicate/retried response must
    // not be able to overwrite an already-recorded Conforme.
    await acceptAll();
    final pending = await repo.watchThesis(id).first;
    expect(pending!.status, ThesisStatus.nominationPendingCoordinator);

    await expectLater(
      repo.respondToNomination(
          thesisId: id,
          nomineeUid: 'p1',
          accept: false,
          declineReason: 'late'),
      throwsA(isA<StateError>()),
    );

    final noms = await repo.watchNominations(id).first;
    final p1 = noms.firstWhere((n) => n.nomineeUid == 'p1');
    expect(p1.conformeStatus, ConformeStatus.accepted,
        reason: 'the late response must not overwrite the earlier record');
  });

  // --- Finding 2: approve() must be atomic with its nomination reads ---

  test(
      'approve() re-reads nominations fresh inside its transaction: a '
      'decline landing mid-flight cannot slip a decliner into '
      'panelistUids[] (regression: non-atomic read-then-write)', () async {
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');

    final approveFuture = repo.approve(thesisId: id, deanUid: 'd1');

    // Simulate a concurrent client declining p3 while approve() is
    // mid-flight, bypassing the repository entirely (as an external write
    // -- a retried client, a second device -- would). The two-microtask
    // delay is an empirically-derived, implementation-coupled number: it
    // lands after approve()'s upfront nomination-id query but while its
    // per-document transaction reads are still in flight. See the task-6
    // fix-1 report for how this was derived (by racing the same write
    // against both the pre-fix and post-fix implementation and observing
    // where they diverge) and for the honest limits of this technique.
    unawaited(Future<void>.value().then((_) => Future<void>.value()).then(
        (_) => db
            .collection('theses')
            .doc(id)
            .collection('nominations')
            .doc('p3')
            .update({'conformeStatus': 'declined'})));

    await expectLater(approveFuture, throwsA(isA<StateError>()));
  });
}
