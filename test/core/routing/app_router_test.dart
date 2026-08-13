import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderScope> scopeFor(UserRole role, {required String uid}) async {
  final db = FakeFirebaseFirestore();
  await UserRepository(db).createStudentProfile(
    uid: uid,
    fullName: 'Test User',
    email: 'test@isufst.edu.ph',
  );
  if (role != UserRole.student) {
    await db.collection('users').doc(uid).update({'role': role.value});
  }

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final mockUser = MockUser(
    uid: uid,
    email: 'test@isufst.edu.ph',
    isEmailVerified: true,
  );

  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(
          signedIn: true,
          mockUser: mockUser,
        ),
      ),
      authStateProvider.overrideWith((ref) => Stream.value(mockUser as User?)),
    ],
    child: const EThesisHubApp(),
  );
}

void main() {
  testWidgets('student lands on the student dashboard', (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.student, uid: 'u1'));
    await tester.pumpAndSettle();
    expect(find.text('My Thesis'), findsOneWidget);
  });

  testWidgets('faculty lands on the faculty dashboard', (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.faculty, uid: 'u2'));
    await tester.pumpAndSettle();
    expect(find.text('My Advisees'), findsOneWidget);
  });

  testWidgets('coordinator lands on the coordinator dashboard',
      (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.coordinator, uid: 'u3'));
    await tester.pumpAndSettle();
    expect(find.text('All Theses'), findsOneWidget);
  });

  testWidgets('dean lands on the dean dashboard', (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.dean, uid: 'u4'));
    await tester.pumpAndSettle();
    expect(find.text('College Overview'), findsOneWidget);
  });
}
