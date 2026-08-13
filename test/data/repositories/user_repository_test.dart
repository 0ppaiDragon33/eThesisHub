import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late UserRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = UserRepository(db);
  });

  test('createStudentProfile always writes the student role', () async {
    await repo.createStudentProfile(
      uid: 'uid-1',
      fullName: 'Karl Joshua P. Vargas',
      email: 'kjvargas@isufst.edu.ph',
      program: 'BSIT',
    );

    final user = await repo.fetchUser('uid-1');
    expect(user!.role, UserRole.student);
    expect(user.program, 'BSIT');
  });

  test('fetchUser returns null for an unknown uid', () async {
    expect(await repo.fetchUser('missing'), isNull);
  });

  test('fetchInviteRole finds an invite by lowercased email', () async {
    await repo.createInvite(
      email: 'Reyes@ISUFST.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator-uid',
    );

    expect(
      await repo.fetchInviteRole('reyes@isufst.edu.ph'),
      UserRole.faculty,
    );
  });

  test('promoteFromInvite upgrades the user and marks the invite consumed',
      () async {
    await repo.createStudentProfile(
      uid: 'uid-2',
      fullName: 'Dr. Reyes',
      email: 'reyes@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'reyes@isufst.edu.ph',
      role: UserRole.coordinator,
      invitedBy: 'seed',
    );

    final newRole = await repo.promoteFromInvite(
      uid: 'uid-2',
      email: 'reyes@isufst.edu.ph',
    );

    expect(newRole, UserRole.coordinator);
    expect((await repo.fetchUser('uid-2'))!.role, UserRole.coordinator);

    // The invite document still exists (never deleted) but is now consumed,
    // so fetchInviteRole treats it as absent.
    final inviteDoc =
        await db.collection('facultyInvites').doc('reyes@isufst.edu.ph').get();
    expect(inviteDoc.exists, isTrue);
    expect(inviteDoc.data()!['consumedAt'], isNotNull);
    expect(await repo.fetchInviteRole('reyes@isufst.edu.ph'), isNull);
  });

  test('a consumed invite cannot promote a second time', () async {
    await repo.createStudentProfile(
      uid: 'uid-5',
      fullName: 'Dr. Santos',
      email: 'santos@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'santos@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'seed',
    );

    final firstRole = await repo.promoteFromInvite(
      uid: 'uid-5',
      email: 'santos@isufst.edu.ph',
    );
    expect(firstRole, UserRole.faculty);

    // Simulate a second user somehow reusing the same (now-consumed) invite.
    await repo.createStudentProfile(
      uid: 'uid-6',
      fullName: 'Imposter',
      email: 'santos2@isufst.edu.ph',
    );
    final secondRole = await repo.promoteFromInvite(
      uid: 'uid-6',
      email: 'santos@isufst.edu.ph',
    );

    expect(secondRole, isNull);
    expect((await repo.fetchUser('uid-6'))!.role, UserRole.student);
  });

  test('promoteFromInvite is a no-op without an invite', () async {
    await repo.createStudentProfile(
      uid: 'uid-3',
      fullName: 'Student',
      email: 'student@isufst.edu.ph',
    );

    final newRole = await repo.promoteFromInvite(
      uid: 'uid-3',
      email: 'student@isufst.edu.ph',
    );

    expect(newRole, isNull);
    expect((await repo.fetchUser('uid-3'))!.role, UserRole.student);
  });

  test('watchUser emits updates', () async {
    await repo.createStudentProfile(
      uid: 'uid-4',
      fullName: 'Watched',
      email: 'watched@isufst.edu.ph',
    );

    await expectLater(
      repo.watchUser('uid-4').map((u) => u?.fullName),
      emits('Watched'),
    );
  });
}
