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


void main() {
  testWidgets('a student types their program and specialization and saves',
      (tester) async {
    final db = await pump(tester, {
      'fullName': 'Ana Cruz',
      'role': 'student',
      'program': 'BSIT',
      'specialization': null,
    });

    expect(
      tester.widget<TextField>(find.byKey(const Key('profileProgram'))).controller!.text,
      'BSIT',
    );
    await tester.enterText(
        find.byKey(const Key('profileSpecialization')), 'Software Development');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    final saved = (await db.doc('users/u1').get()).data()!;
    expect(saved['program'], 'BSIT');
    expect(saved['specialization'], 'Software Development');
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('any program or specialization name is accepted',
      (tester) async {
    final db = await pump(tester, {
      'fullName': 'Ben Reyes',
      'role': 'student',
    });
    await tester.enterText(find.byKey(const Key('profileProgram')), 'BSEMC');
    await tester.enterText(
        find.byKey(const Key('profileSpecialization')), 'Game Development');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    final saved = (await db.doc('users/u1').get()).data()!;
    expect(saved['program'], 'BSEMC');
    expect(saved['specialization'], 'Game Development');
  });

  testWidgets('clearing a box stores nothing for it', (tester) async {
    final db = await pump(tester, {
      'fullName': 'Ana Cruz',
      'role': 'student',
      'program': 'BSIT',
      'specialization': 'Networking',
    });
    await tester.enterText(find.byKey(const Key('profileSpecialization')), '  ');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    expect((await db.doc('users/u1').get()).data()!['specialization'], isNull);
  });

  testWidgets('faculty see no program box and type their specialization',
      (tester) async {
    final db = await pump(tester, {
      'fullName': 'Dr. Parcia',
      'role': 'faculty',
      'college': 'CICI',
      'specialization': 'MIT',
    });
    expect(find.byKey(const Key('profileProgram')), findsNothing);
    expect(find.text('CICI'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profileSpecialization')), 'MSCS');
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
