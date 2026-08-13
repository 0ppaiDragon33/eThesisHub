import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderContainer> containerFor(UserRole role, {required String uid}) async {
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

  return ProviderContainer(
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
  );
}

Future<ProviderContainer> containerForSignedOut() async {
  final db = FakeFirebaseFirestore();

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: false),
      ),
      authStateProvider.overrideWith((ref) => Stream.value(null)),
    ],
  );
}

void main() {
  testWidgets('student lands on the student dashboard', (tester) async {
    final container = await containerFor(UserRole.student, uid: 'u1');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Thesis'), findsOneWidget);
  });

  testWidgets('faculty lands on the faculty dashboard', (tester) async {
    final container = await containerFor(UserRole.faculty, uid: 'u2');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Advisees'), findsOneWidget);
  });

  testWidgets('coordinator lands on the coordinator dashboard',
      (tester) async {
    final container = await containerFor(UserRole.coordinator, uid: 'u3');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('All Theses'), findsOneWidget);
  });

  testWidgets('dean lands on the dean dashboard', (tester) async {
    final container = await containerFor(UserRole.dean, uid: 'u4');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('College Overview'), findsOneWidget);
  });

  testWidgets('student cannot reach the dean dashboard', (tester) async {
    final container = await containerFor(UserRole.student, uid: 'u1');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Thesis'), findsOneWidget);

    // Attempt to reach another role's dashboard by route.
    container.read(goRouterProvider).go('/dean');
    await tester.pumpAndSettle();

    // Should be redirected back to student dashboard
    expect(find.text('College Overview'), findsNothing);
    expect(find.text('My Thesis'), findsOneWidget);
  });

  testWidgets('faculty cannot reach the coordinator dashboard', (tester) async {
    final container = await containerFor(UserRole.faculty, uid: 'u2');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Advisees'), findsOneWidget);

    // Attempt to reach another role's dashboard by route.
    container.read(goRouterProvider).go('/coordinator');
    await tester.pumpAndSettle();

    // Should be redirected back to faculty dashboard
    expect(find.text('All Theses'), findsNothing);
    expect(find.text('My Advisees'), findsOneWidget);
  });

  testWidgets('signed-out user can reach registration from sign-in',
      (tester) async {
    final container = await containerForSignedOut();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Should be on Sign in screen
    expect(find.text('Sign in'), findsWidgets);

    // Tap the "goToRegister" button to navigate to registration
    await tester.tap(find.byKey(const Key('goToRegister')));
    await tester.pumpAndSettle();

    // Should be on Create account screen
    expect(find.text('Create account'), findsWidgets);
  });

  testWidgets('signed-out user can get back to sign-in from registration',
      (tester) async {
    final container = await containerForSignedOut();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to registration screen
    container.read(goRouterProvider).go('/register');
    await tester.pumpAndSettle();

    // Should be on Create account screen
    expect(find.text('Create account'), findsWidgets);

    // Tap the "goToLogin" button to navigate back to sign-in
    await tester.tap(find.byKey(const Key('goToLogin')));
    await tester.pumpAndSettle();

    // Should be back on Sign in screen
    expect(find.text('Sign in'), findsWidgets);
  });
}
