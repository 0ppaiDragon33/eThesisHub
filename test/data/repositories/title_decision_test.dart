import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';
import 'package:ethesishub/data/services/audit_service.dart';

Future<FakeFirebaseFirestore> pending() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'status': 'titlePendingDefence',
    'panelistUids': <String>[], 'adviserUid': 'a1',
    'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    'titleRound': 1,
  });
  await db.collection('theses/t1/candidateTitles').doc('ct1').set({
    'titleText': 'Candidate one', 'justificationPath': 'p',
    'justificationUrl': 'u', 'round': 1,
  });
  return db;
}

void main() {
  test('approving records the title and who decided', () async {
    final db = await pending();
    await TitleDefenceRepository(db)
        .approveTitle(thesisId: 't1', candidateTitleId: 'ct1', deanUid: 'd1');

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], ThesisStatus.titleApproved.value);
    expect(t['approvedTitleId'], 'ct1');
    expect(t['titleDecidedBy'], 'd1');
    expect(t['titleDecidedAt'], isNotNull);
  });

  test('approving a candidate that is not on this thesis is refused',
      () async {
    final repo = TitleDefenceRepository(await pending());
    expect(
      () => repo.approveTitle(
          thesisId: 't1', candidateTitleId: 'ghost', deanUid: 'd1'),
      throwsArgumentError,
    );
  });

  test('rejecting requires a remark', () async {
    // The student must always know what to fix. Mirrors the decline reason
    // already required in the Conforme step.
    final repo = TitleDefenceRepository(await pending());
    expect(
      () => repo.rejectTitles(thesisId: 't1', deanUid: 'd1', remark: '  '),
      throwsArgumentError,
    );
  });

  test('rejecting records the remark and the decision', () async {
    final db = await pending();
    await TitleDefenceRepository(db).rejectTitles(
        thesisId: 't1', deanUid: 'd1', remark: 'All three are too broad.');

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], ThesisStatus.titleRejected.value);
    expect(t['titleRejectionRemark'], 'All three are too broad.');
    expect(t['titleDecidedBy'], 'd1');
  });

  test('a decision cannot be replayed once made', () async {
    // Same defect class M1a found in respondToNomination, where a stale tab
    // could walk an approved thesis backwards.
    final db = await pending();
    final repo = TitleDefenceRepository(db);
    await repo.approveTitle(
        thesisId: 't1', candidateTitleId: 'ct1', deanUid: 'd1');
    expect(
      () => repo.rejectTitles(
          thesisId: 't1', deanUid: 'd1', remark: 'changed my mind'),
      throwsStateError,
    );
  });

  test('both decisions leave an audit entry naming the Dean', () async {
    // Spec §9.2: the rules cannot verify that the approved candidate belongs
    // to the current round, so a Dean could approve one from a superseded
    // set. The audit log is the stated mitigation — if nothing writes it,
    // the limitation has no mitigation at all.
    final db = await pending();
    await TitleDefenceRepository(db)
        .approveTitle(thesisId: 't1', candidateTitleId: 'ct1', deanUid: 'd1');

    final logs = await db.collection('auditLogs').get();
    expect(logs.docs, hasLength(1));
    final entry = logs.docs.first.data();
    expect(entry['action'], 'title.approved');
    expect(entry['actorUid'], 'd1');
    expect(entry['targetId'], 't1');
    expect((entry['metadata'] as Map)['approvedTitleId'], 'ct1');
  });

  test('a failed audit write does not block the decision', () async {
    // Same posture as M1a's sign-in path: the decision is the point, the log
    // is best-effort. A thesis must not be left undecided because a log
    // write failed.
    final db = await pending();
    final repo = TitleDefenceRepository(db, audit: _FailingAudit());
    await repo.rejectTitles(
        thesisId: 't1', deanUid: 'd1', remark: 'All too broad.');

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], 'titleRejected');
  });
}

class _FailingAudit implements AuditService {
  @override
  Future<void> log({
    required String actorUid,
    required String action,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? metadata,
  }) async {
    throw Exception('audit unavailable');
  }
}
