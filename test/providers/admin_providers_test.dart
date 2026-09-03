import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/providers/admin_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Map<String, dynamic> userDoc(String fullName, {bool active = true}) => {
      'fullName': fullName,
      'email': '${fullName.toLowerCase()}@isufst.edu.ph',
      'role': 'faculty',
      'active': active,
      'createdAt': FieldValue.serverTimestamp(),
    };

ProviderContainer buildContainer(FakeFirebaseFirestore db) {
  final container = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'coord',
        email: 'coord@isufst.edu.ph',
        isEmailVerified: true,
      ),
    )),
  ]);
  return container;
}

void main() {
  test('allUsersProvider returns every seeded account, sorted by name',
      () async {
    final db = FakeFirebaseFirestore();
    // Seeded against alphabetical order: a fixture inserted in the expected
    // order would still pass with the sort deleted.
    await db.collection('users').doc('u1').set(userDoc('Zara'));
    await db.collection('users').doc('u2').set(userDoc('Alma'));

    final container = buildContainer(db);
    addTearDown(container.dispose);

    final all = await container.read(allUsersProvider.future);
    expect(all, hasLength(2));
    expect(all.map((u) => u.fullName).toList(), ['Alma', 'Zara']);
  });

  test('setActive flips the active flag', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma', active: true));

    final repo = UserRepository(db);
    await repo.setActive('u1', false);

    final snap = await db.collection('users').doc('u1').get();
    expect(snap.data()!['active'], false);
  });

  test('setDesignation writes both fields to users', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma'));

    final repo = UserRepository(db);
    await repo.setDesignation(uid: 'u1', adviser: false, panelist: true);

    final snap = await db.collection('users').doc('u1').get();
    expect(snap.data()!['nominableAsAdviser'], false);
    expect(snap.data()!['nominableAsPanelist'], true);
  });

  test('setDesignation mirrors to an existing directory entry', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma'));
    await db.collection('facultyDirectory').doc('u1').set({
      'fullName': 'Alma',
      'role': 'faculty',
    });

    final repo = UserRepository(db);
    await repo.setDesignation(uid: 'u1', adviser: false, panelist: false);

    final snap = await db.collection('facultyDirectory').doc('u1').get();
    expect(snap.data()!['nominableAsAdviser'], false);
    expect(snap.data()!['nominableAsPanelist'], false);
  });

  test(
      'setDesignation does not create a directory entry when none exists',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma'));

    final repo = UserRepository(db);
    await repo.setDesignation(uid: 'u1', adviser: true, panelist: false);

    final snap = await db.collection('facultyDirectory').doc('u1').get();
    expect(snap.exists, isFalse);
  });

  test('FacultyDirectoryRepository.setDesignation never creates via set',
      () async {
    final db = FakeFirebaseFirestore();
    final repo = FacultyDirectoryRepository(db);

    // No entry exists for 'ghost' -- update on a missing doc throws
    // not-found, and the repository must let that propagate (the caller
    // decides whether to swallow it).
    await expectLater(
      () => repo.setDesignation(uid: 'ghost', adviser: true, panelist: true),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'not-found')),
    );
  });
}
