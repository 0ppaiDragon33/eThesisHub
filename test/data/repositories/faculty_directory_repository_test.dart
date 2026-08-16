import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';

AppUser user(String uid, String name, UserRole role) => AppUser(
      uid: uid,
      fullName: name,
      email: '$uid@isufst.edu.ph',
      role: role,
      active: true,
      createdAt: DateTime.utc(2026, 8, 14),
      college: 'CICT',
    );

void main() {
  late FakeFirebaseFirestore db;
  late FacultyDirectoryRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FacultyDirectoryRepository(db);
  });

  test('upsert writes an entry for faculty', () async {
    await repo.upsertOwnEntry(user('f1', 'Dr. Armada', UserRole.faculty));
    final entry = await repo.fetch('f1');
    expect(entry!.fullName, 'Dr. Armada');
    expect(entry.role, 'faculty');
  });

  test('upsert never writes an entry for a student', () async {
    await repo.upsertOwnEntry(user('s1', 'A Student', UserRole.student));
    expect(await repo.fetch('s1'), isNull);
  });

  test('the entry never contains an email', () async {
    await repo.upsertOwnEntry(user('f2', 'Dr. Diamante', UserRole.faculty));
    final raw = await db.collection('facultyDirectory').doc('f2').get();
    expect(raw.data()!.containsKey('email'), isFalse);
  });

  // Replaces the `watchSelectableFaculty` (faculty-only) test that stood
  // here. That method and its provider were removed as dead: nothing in
  // `lib/` watched them, and under the owner's ruling that coordinators and
  // the dean stay nominable, a faculty-only slice can never be the right
  // source for a picker. `watchAllDirectory` is the path that actually ships,
  // and it had no repository-level test of its own — so the coverage moves
  // here rather than disappearing.
  test('watchAllDirectory includes coordinators and the dean, sorted by name',
      () async {
    await repo.upsertOwnEntry(user('f3', 'Dr. Zamora', UserRole.faculty));
    await repo.upsertOwnEntry(user('c1', 'Dr. Bito-onon', UserRole.coordinator));
    await repo.upsertOwnEntry(user('d1', 'Dr. Siason', UserRole.dean));

    final all = await repo.watchAllDirectory().first;
    // Every role is offered — this is exactly what the faculty-only slice
    // got wrong — and the order is by full name, not by insertion.
    expect(all.map((e) => e.uid), ['c1', 'd1', 'f3']);
    expect(all.map((e) => e.role), ['coordinator', 'dean', 'faculty']);
  });

  test('fetchExOfficio returns coordinators and deans only', () async {
    await repo.upsertOwnEntry(user('f4', 'Dr. Faculty', UserRole.faculty));
    await repo.upsertOwnEntry(user('c2', 'Dr. Coordinator', UserRole.coordinator));
    await repo.upsertOwnEntry(user('d2', 'Dr. Dean', UserRole.dean));

    final ex = await repo.fetchExOfficio();
    expect(ex.map((e) => e.uid).toSet(), {'c2', 'd2'});
  });
}
