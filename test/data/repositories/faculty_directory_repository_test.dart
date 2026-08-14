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

  test('selectable faculty excludes coordinators and deans', () async {
    await repo.upsertOwnEntry(user('f3', 'Dr. Faculty', UserRole.faculty));
    await repo.upsertOwnEntry(user('c1', 'Dr. Coordinator', UserRole.coordinator));
    await repo.upsertOwnEntry(user('d1', 'Dr. Dean', UserRole.dean));

    final selectable = await repo.watchSelectableFaculty().first;
    expect(selectable.map((e) => e.uid), ['f3']);
  });

  test('fetchExOfficio returns coordinators and deans only', () async {
    await repo.upsertOwnEntry(user('f4', 'Dr. Faculty', UserRole.faculty));
    await repo.upsertOwnEntry(user('c2', 'Dr. Coordinator', UserRole.coordinator));
    await repo.upsertOwnEntry(user('d2', 'Dr. Dean', UserRole.dean));

    final ex = await repo.fetchExOfficio();
    expect(ex.map((e) => e.uid).toSet(), {'c2', 'd2'});
  });
}
