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

  test('a sign-in does not wipe Console-set college and specialization',
      () async {
    // The only way these two fields get set at all today is by hand in the
    // Firebase Console: registration collects a program but never a college,
    // `createStudentProfile` hardcodes `specialization: null`, and
    // `promoteFromInvite` touches only `role`. So a real faculty profile
    // reaches `upsertOwnEntry` with both null.
    //
    // The entry as an administrator left it:
    await db.collection('facultyDirectory').doc('f9').set({
      'fullName': 'Dr. Padojinog',
      'role': 'faculty',
      'college': 'CICT',
      'specialization': 'Software Engineering',
    });

    // ...and then that person signs in, carrying a profile with neither.
    await repo.upsertOwnEntry(AppUser(
      uid: 'f9',
      fullName: 'Dr. Padojinog',
      email: 'f9@isufst.edu.ph',
      role: UserRole.faculty,
      active: true,
      createdAt: DateTime.utc(2026, 8, 14),
    ));

    final entry = await repo.fetch('f9');
    expect(entry!.college, 'CICT',
        reason: 'a plain set() would have overwritten this with null');
    expect(entry.specialization, 'Software Engineering');
    // Which is what the picker actually renders under the name.
    expect(entry.subtitle, 'CICT · Software Engineering');
  });

  test('a profile that does carry a college still writes it', () async {
    // Falsifiability control for the merge above: skipping null fields must
    // not turn into skipping the field always. `user()` supplies 'CICT'.
    await repo.upsertOwnEntry(user('f10', 'Dr. Braganza', UserRole.faculty));
    expect((await repo.fetch('f10'))!.college, 'CICT');
  });

  test('the app still owns fullName and role on every sign-in', () async {
    // The other half of the split: a stale name or a role the invite has
    // since changed must be corrected by the sign-in, not preserved by it.
    await db.collection('facultyDirectory').doc('f11').set({
      'fullName': 'Old Name',
      'role': 'faculty',
      'college': 'CICT',
    });

    await repo.upsertOwnEntry(user('f11', 'Dr. Bito-onon', UserRole.coordinator));

    final entry = await repo.fetch('f11');
    expect(entry!.fullName, 'Dr. Bito-onon');
    expect(entry.role, 'coordinator',
        reason: 'a promotion must reach the directory, or the ex-officio '
            'picker keeps missing a coordinator');
    expect(entry.college, 'CICT');
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
