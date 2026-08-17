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

  test(
      'watchThesis converts non-null coordinatorRecommendedAt, deanApprovedAt '
      'and nominationsSubmittedAt', () async {
    // Every nullable timestamp field gets its own distinct value on purpose:
    // a helper that reads the wrong map key (e.g. `_toThesis` copy-pasting
    // `coordinatorRecommendedAt`'s line for `nominationsSubmittedAt` without
    // changing the key) would still pass if two fields shared a value, and
    // would only be caught with every value different from every other.
    final createdAt = DateTime.utc(2026, 1, 1);
    final coordinatorAt = DateTime.utc(2026, 3, 1, 9, 0, 0);
    final deanAt = DateTime.utc(2026, 4, 15, 14, 30, 0);
    final nominationsSubmittedAt = DateTime.utc(2026, 2, 10, 11, 45, 0);
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
      'nominationsSubmittedAt': Timestamp.fromDate(nominationsSubmittedAt),
      'createdAt': Timestamp.fromDate(createdAt),
    });

    final thesis = await repo.watchThesis(doc.id).first;

    expect(thesis!.coordinatorRecommendedAt!.toUtc(), coordinatorAt);
    expect(thesis.deanApprovedAt!.toUtc(), deanAt);
    expect(thesis.nominationsSubmittedAt!.toUtc(), nominationsSubmittedAt);
  });

  test(
      'watchThesis converts titlesSubmittedAt and titleDecidedAt, seeded '
      'exactly as approveTitle/rejectTitles write them', () async {
    // Reproduces the shape production actually writes: real Firestore
    // Timestamp values (not DateTime, which is what the earlier version of
    // this test file — and Thesis.fromMap's bare `as DateTime?` cast — could
    // both pass without ever exercising the conversion). Distinct values on
    // both fields so a helper that reads the wrong key (e.g. assigning
    // titlesSubmittedAt's value to titleDecidedAt) cannot hide behind a
    // shared value.
    final titlesSubmittedAt = DateTime.utc(2026, 5, 1, 10, 0, 0);
    final titleDecidedAt = DateTime.utc(2026, 5, 20, 16, 45, 0);
    final doc = db.collection('theses').doc();
    await doc.set({
      'leaderUid': 'leader-1',
      'workingTitle': 'eThesisHub',
      'memberNames': ['Bagsain, Karlo June'],
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': ThesisStatus.titleRejected.value,
      'adviserUid': 'adviser-1',
      'panelistUids': <String>[],
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'titleRound': 1,
      'titlesSubmittedAt': Timestamp.fromDate(titlesSubmittedAt),
      'titleDecidedAt': Timestamp.fromDate(titleDecidedAt),
      'titleDecidedBy': 'dean-1',
      'titleRejectionRemark': 'Scope too broad.',
    });

    final thesis = await repo.watchThesis(doc.id).first;

    expect(thesis, isNotNull);
    expect(thesis!.titlesSubmittedAt!.toUtc(), titlesSubmittedAt);
    expect(thesis.titleDecidedAt!.toUtc(), titleDecidedAt);
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
