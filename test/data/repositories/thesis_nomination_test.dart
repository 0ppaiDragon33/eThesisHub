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
}
