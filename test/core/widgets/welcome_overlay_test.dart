import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/widgets/welcome_overlay.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

AppUser karl() => AppUser(
      uid: 'u1',
      fullName: 'Karl Joshua Vargas',
      email: 'k@isufst.edu.ph',
      role: UserRole.student,
      active: true,
      createdAt: DateTime(2026),
    );

Future<ProviderContainer> pumpOverlay(
  WidgetTester tester, {
  required bool pending,
}) async {
  final container = ProviderContainer(overrides: [
    currentUserProvider.overrideWith((ref) => Stream.value(karl())),
  ]);
  addTearDown(container.dispose);
  container.read(welcomePendingProvider.notifier).state = pending;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: WelcomeOverlay(child: Scaffold(body: Text('DASHBOARD'))),
    ),
  ));
  await tester.pump();
  return container;
}

/// Signs in with any password; or refuses every one with [failWith].
class FakeSignIn extends AuthService {
  FakeSignIn({this.failWith}) : super(MockFirebaseAuth());

  final String? failWith;

  @override
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    if (failWith != null) throw FirebaseAuthException(code: failWith!);
    return MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', email: email, isEmailVerified: true),
    ).signInWithEmailAndPassword(email: email, password: password);
  }
}

void main() {
  test('the title greets by first name', () {
    expect(welcomeTitle('Karl Joshua Vargas'), 'Welcome back, Karl');
    expect(welcomeTitle('  Ana  '), 'Welcome back, Ana');
    expect(welcomeTitle(''), 'Welcome back');
    expect(welcomeTitle(null), 'Welcome back');
  });

  testWidgets('right after sign-in the welcome shows, then clears itself',
      (tester) async {
    final container = await pumpOverlay(tester, pending: true);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('welcomeSplash')), findsOneWidget);
    expect(find.text('Welcome back, Karl'), findsOneWidget);
    expect(find.text('Signed in successfully!'), findsOneWidget);
    expect(find.text('Redirecting to your dashboard…'), findsOneWidget);
    expect(container.read(welcomePendingProvider), isFalse,
        reason: 'shown once per sign-in');

    await tester.pump(welcomeHold);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcomeSplash')), findsNothing);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('opening the app already signed in shows no welcome',
      (tester) async {
    await pumpOverlay(tester, pending: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcomeSplash')), findsNothing);
  });

  group('the sign-in screen', () {
    Future<ProviderContainer> pumpLogin(
        WidgetTester tester, AuthService auth) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
        authServiceProvider.overrideWithValue(auth),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ));
      await tester.enterText(find.byKey(const Key('email')), 'k@isufst.edu.ph');
      await tester.enterText(find.byKey(const Key('password')), 'secret123');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a successful sign-in asks for the welcome', (tester) async {
      final container = await pumpLogin(tester, FakeSignIn());
      expect(container.read(welcomePendingProvider), isTrue);
    });

    testWidgets('a wrong password does not', (tester) async {
      final container =
          await pumpLogin(tester, FakeSignIn(failWith: 'invalid-credential'));
      expect(container.read(welcomePendingProvider), isFalse);
      expect(find.textContaining('Incorrect'), findsOneWidget);
    });
  });
}
