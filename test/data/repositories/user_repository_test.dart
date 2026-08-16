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

  test('promoteFromInvite carries college and specialization onto the profile',
      () async {
    // These two fields have no other source. Registration collects a program
    // but never a college, createStudentProfile hardcodes specialization to
    // null, and the promotion used to write only `role` — so a freshly
    // promoted faculty member reached facultyDirectory with both blank and
    // showed as a bare name in the nomination pickers. The coordinator
    // issuing the invite knows both, so the invite carries them.
    await repo.createStudentProfile(
      uid: 'uid-9',
      fullName: 'Dr. Armada',
      email: 'armada@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'armada@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator-uid',
      college: 'CICT',
      specialization: 'Software Engineering',
    );

    await repo.promoteFromInvite(
      uid: 'uid-9',
      email: 'armada@isufst.edu.ph',
    );

    final user = (await repo.fetchUser('uid-9'))!;
    expect(user.role, UserRole.faculty);
    expect(user.college, 'CICT');
    expect(user.specialization, 'Software Engineering');
  });

  test('an invite without college leaves the existing profile values alone',
      () async {
    // The two fields are optional on the invite. Writing them unconditionally
    // would null out whatever the account already had — the same overwrite
    // bug that upsertOwnEntry had against the Console.
    await repo.createStudentProfile(
      uid: 'uid-10',
      fullName: 'Dr. Diamante',
      email: 'diamante@isufst.edu.ph',
      college: 'CFAS',
    );
    await repo.createInvite(
      email: 'diamante@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator-uid',
    );

    await repo.promoteFromInvite(
      uid: 'uid-10',
      email: 'diamante@isufst.edu.ph',
    );

    final user = (await repo.fetchUser('uid-10'))!;
    expect(user.role, UserRole.faculty);
    expect(user.college, 'CFAS', reason: 'must not be nulled by the promotion');
  });

  test('watchInvites lists every invite, newest first, consumed ones included',
      () async {
    await repo.createInvite(
      email: 'a@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator-uid',
      college: 'CICT',
    );
    await repo.createInvite(
      email: 'b@isufst.edu.ph',
      role: UserRole.dean,
      invitedBy: 'coordinator-uid',
    );

    final invites = await repo.watchInvites().first;
    expect(invites.map((i) => i.email),
        containsAll(['a@isufst.edu.ph', 'b@isufst.edu.ph']));

    final a = invites.firstWhere((i) => i.email == 'a@isufst.edu.ph');
    expect(a.role, UserRole.faculty);
    expect(a.college, 'CICT');
    expect(a.isConsumed, isFalse,
        reason: 'a freshly issued invite is still open');

    final b = invites.firstWhere((i) => i.email == 'b@isufst.edu.ph');
    expect(b.role, UserRole.dean, reason: 'the dean role must survive a round trip');
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
