import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The picker lists `facultyDirectory`, and a person's own entry there used
/// to be written by the sign-in screen, which the router has already
/// replaced by then. It is written from `ownDirectoryEntrySyncProvider`,
/// which the signed-in shell keeps alive.
Future<ProviderContainer> start(
  FakeFirebaseFirestore db, {
  required String uid,
}) async {
  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: '$uid@isufst.edu.ph',
            isEmailVerified: true,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Held open like AppShellHost does.
  container.listen(ownDirectoryEntrySyncProvider, (_, _) {});
  // Let the profile stream and the write land.
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container;
}

Future<void> seedUser(
  FakeFirebaseFirestore db,
  String uid,
  String role, {
  bool active = true,
  Map<String, dynamic> extra = const {},
}) =>
    db.collection('users').doc(uid).set({
      'fullName': 'Name $uid',
      'email': '$uid@isufst.edu.ph',
      'role': role,
      'active': active,
      'college': 'CICT',
      ...extra,
    });

void main() {
  test('a faculty member gets a directory entry with no designation written',
      () async {
    final db = FakeFirebaseFirestore();
    await seedUser(db, 'f1', 'faculty');
    await start(db, uid: 'f1');

    final entry = await db.doc('facultyDirectory/f1').get();
    expect(entry.exists, isTrue);
    expect(entry.data()!['fullName'], 'Name f1');
    expect(entry.data()!['role'], 'faculty');
    expect(entry.data()!['college'], 'CICT');
    // Absent means nominable for both; the sync must not decide that.
    expect(entry.data()!.containsKey('nominableAsAdviser'), isFalse);
    expect(entry.data()!.containsKey('nominableAsPanelist'), isFalse);
  });

  test('coordinators and the dean get one too', () async {
    final db = FakeFirebaseFirestore();
    await seedUser(db, 'c1', 'coordinator');
    await start(db, uid: 'c1');
    expect((await db.doc('facultyDirectory/c1').get()).exists, isTrue);

    final db2 = FakeFirebaseFirestore();
    await seedUser(db2, 'd1', 'dean');
    await start(db2, uid: 'd1');
    expect((await db2.doc('facultyDirectory/d1').get()).exists, isTrue);
  });

  test('a student gets none', () async {
    final db = FakeFirebaseFirestore();
    await seedUser(db, 's1', 'student');
    await start(db, uid: 's1');
    expect((await db.doc('facultyDirectory/s1').get()).exists, isFalse);
  });

  test('a deactivated account gets none', () async {
    final db = FakeFirebaseFirestore();
    await seedUser(db, 'f1', 'faculty', active: false);
    await start(db, uid: 'f1');
    expect((await db.doc('facultyDirectory/f1').get()).exists, isFalse);
  });

  test('a coordinator\'s designation on an existing entry is left alone',
      () async {
    final db = FakeFirebaseFirestore();
    await seedUser(db, 'f1', 'faculty');
    await db.doc('facultyDirectory/f1').set({
      'fullName': 'Old Name',
      'role': 'faculty',
      'nominableAsAdviser': false,
      'nominableAsPanelist': true,
    });
    await start(db, uid: 'f1');

    final entry = await db.doc('facultyDirectory/f1').get();
    expect(entry.data()!['fullName'], 'Name f1', reason: 'name refreshed');
    expect(entry.data()!['nominableAsAdviser'], isFalse);
    expect(entry.data()!['nominableAsPanelist'], isTrue);
  });

  test('a signed-out session writes nothing', () async {
    final db = FakeFirebaseFirestore();
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(ownDirectoryEntrySyncProvider, (_, _) {});
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect((await db.collection('facultyDirectory').get()).docs, isEmpty);
  });
}
