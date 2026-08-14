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
}
