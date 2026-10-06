import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/profile/profile_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> pump(
  WidgetTester tester,
  Map<String, dynamic> profile,
) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final db = FakeFirebaseFirestore();
  await db.doc('users/u1').set({
    'email': 'u1@isufst.edu.ph',
    'active': true,
    ...profile,
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'u1', email: 'u1@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
  ));
  await tester.pumpAndSettle();
  return db;
}

Future<void> pick(WidgetTester tester, Key field, String option) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a BSIT student picks a specialization and saves it',
      (tester) async {
    final db = await pump(tester, {
      'fullName': 'Ana Cruz',
      'role': 'student',
      'program': 'BSIT',
      'specialization': null,
    });

    // BSIT's three specializations are offered.
    await tester.tap(find.byKey(const ValueKey('profileSpecialization-BSIT')));
    await tester.pumpAndSettle();
    for (final s in [
      'Artificial Intelligence',
      'Software Development',
      'Networking',
    ]) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    await tester.tap(find.text('Software Development').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    final saved = (await db.doc('users/u1').get()).data()!;
    expect(saved['specialization'], 'Software Development');
    expect(saved['program'], 'BSIT');
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('a program with no list offers no specialization',
      (tester) async {
    await pump(tester, {
      'fullName': 'Ben Reyes',
      'role': 'student',
      'program': 'BSIT',
    });
    await pick(tester, const Key('profileProgram'), 'BSCS');
    expect(find.byKey(const ValueKey('profileSpecialization-BSCS')),
        findsNothing);
  });

  testWidgets('switching program clears a specialization it does not offer',
      (tester) async {
    final db = await pump(tester, {
      'fullName': 'Ana Cruz',
      'role': 'student',
      'program': 'BSIT',
      'specialization': 'Networking',
    });
    await pick(tester, const Key('profileProgram'), 'BSCS');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    final saved = (await db.doc('users/u1').get()).data()!;
    expect(saved['program'], 'BSCS');
    expect(saved['specialization'], isNull);
  });

  testWidgets('faculty type their specialization freely', (tester) async {
    final db = await pump(tester, {
      'fullName': 'Dr. Parcia',
      'role': 'faculty',
      'college': 'CICI',
      'specialization': 'MIT',
    });
    expect(find.byKey(const Key('profileProgram')), findsNothing);
    expect(find.text('CICI'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('profileFacultySpecialization')), 'MSCS');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    expect((await db.doc('users/u1').get()).data()!['specialization'], 'MSCS');
  });

  testWidgets('an empty name is refused before any write', (tester) async {
    final db = await pump(tester, {
      'fullName': 'Ana Cruz',
      'role': 'student',
    });
    await tester.enterText(find.byKey(const Key('profileName')), '   ');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your full name.'), findsOneWidget);
    expect((await db.doc('users/u1').get()).data()!['fullName'], 'Ana Cruz');
  });
}
