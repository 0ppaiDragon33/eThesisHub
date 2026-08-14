import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ThesisRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
  });

  Future<String> create() => repo.createThesis(
        leaderUid: 'leader-1',
        workingTitle: 'eThesisHub',
        memberNames: ['Bagsain, Karlo June'],
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
      );

  test('createThesis stores a draft owned by the leader', () async {
    final id = await create();
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.leaderUid, 'leader-1');
    expect(thesis.status, ThesisStatus.draft);
    expect(thesis.panelistUids, isEmpty);
    expect(thesis.adviserUid, isNull);
    expect(thesis.memberNames, ['Bagsain, Karlo June']);
  });

  test('watchThesisForLeader finds the leader thesis', () async {
    await create();
    final thesis = await repo.watchThesisForLeader('leader-1').first;
    expect(thesis, isNotNull);
    expect(thesis!.workingTitle, 'eThesisHub');
  });

  test('watchThesisForLeader is null for someone else', () async {
    await create();
    expect(await repo.watchThesisForLeader('other').first, isNull);
  });

  test('watchByStatus filters', () async {
    await create();
    final drafts = await repo.watchByStatus(ThesisStatus.draft).first;
    expect(drafts, hasLength(1));
    final pending =
        await repo.watchByStatus(ThesisStatus.nominationPendingDean).first;
    expect(pending, isEmpty);
  });

  test('watchThesis converts non-null coordinatorRecommendedAt and deanApprovedAt',
      () async {
    final coordinatorAt = DateTime.utc(2026, 3, 1, 9, 0, 0);
    final deanAt = DateTime.utc(2026, 4, 15, 14, 30, 0);
    final doc = db.collection('theses').doc();
    await doc.set({
      'leaderUid': 'leader-1',
      'workingTitle': 'eThesisHub',
      'memberNames': ['Bagsain, Karlo June'],
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': ThesisStatus.nominationApproved.value,
      'adviserUid': 'adviser-1',
      'panelistUids': <String>[],
      'coordinatorRecommendedAt': Timestamp.fromDate(coordinatorAt),
      'coordinatorRecommendedBy': 'coordinator-1',
      'deanApprovedAt': Timestamp.fromDate(deanAt),
      'deanApprovedBy': 'dean-1',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });

    final thesis = await repo.watchThesis(doc.id).first;

    expect(thesis!.coordinatorRecommendedAt!.toUtc(), coordinatorAt);
    expect(thesis.deanApprovedAt!.toUtc(), deanAt);
  });

  test('watchNominations converts a non-null respondedAt', () async {
    final respondedAt = DateTime.utc(2026, 2, 10, 8, 15, 0);
    final thesisDoc = db.collection('theses').doc();
    await thesisDoc.set({
      'leaderUid': 'leader-1',
      'workingTitle': 'eThesisHub',
      'memberNames': ['Bagsain, Karlo June'],
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': ThesisStatus.draft.value,
      'adviserUid': null,
      'panelistUids': <String>[],
      'coordinatorRecommendedAt': null,
      'coordinatorRecommendedBy': null,
      'deanApprovedAt': null,
      'deanApprovedBy': null,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });
    await thesisDoc.collection('nominations').doc('nominee-1').set({
      'nomineeName': 'Dr. Santos',
      'position': 'adviser',
      'exOfficio': false,
      'conformeStatus': 'accepted',
      'respondedAt': Timestamp.fromDate(respondedAt),
      'declineReason': null,
    });

    final nominations = await repo.watchNominations(thesisDoc.id).first;

    expect(nominations, hasLength(1));
    expect(nominations.first.respondedAt!.toUtc(), respondedAt);
  });
}
