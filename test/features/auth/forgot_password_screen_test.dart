import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/features/auth/forgot_password_screen.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Records reset emails, and fails with [code] when given one.
class FakeResetService extends AuthService {
  FakeResetService({this.code}) : super(MockFirebaseAuth());

  final String? code;
  final sentTo = <String>[];

  @override
  Future<void> sendPasswordReset(String email) async {
    if (code != null) throw FirebaseAuthException(code: code!);
    sentTo.add(email);
  }
}

void main() {
  /// Sign in at '/login', so the whole path (the link, the page, the way
  /// back) is exercised through the real routes.
  Future<GoRouter> pump(
    WidgetTester tester,
    FakeResetService service, {
    String initial = '/forgot-password',
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/forgot-password',
          builder: (_, state) => ForgotPasswordScreen(
            email: state.uri.queryParameters['email'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
          authServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> send(WidgetTester tester, String email) async {
    await tester.enterText(find.byKey(const Key('email')), email);
    await tester.tap(find.byKey(const Key('sendReset')));
    await tester.pumpAndSettle();
  }

  testWidgets('sends the link and shows a check-your-email page',
      (tester) async {
    final service = FakeResetService();
    await pump(tester, service);

    await send(tester, 'kj@isufst.edu.ph');

    expect(service.sentTo, ['kj@isufst.edu.ph']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('kj@isufst.edu.ph'), findsOneWidget);
    expect(find.byKey(const Key('email')), findsNothing);
  });

  testWidgets('an empty email asks for one and sends nothing', (tester) async {
    final service = FakeResetService();
    await pump(tester, service);

    await tester.tap(find.byKey(const Key('sendReset')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(service.sentTo, isEmpty);
  });

  testWidgets('an unknown address looks the same as a real one',
      (tester) async {
    await pump(tester, FakeResetService(code: 'user-not-found'));

    await send(tester, 'nobody@isufst.edu.ph');

    expect(find.text('Check your email'), findsOneWidget);
    expect(find.byKey(const Key('resetSent')), findsOneWidget);
  });

  testWidgets('a badly formed address is said so', (tester) async {
    await pump(tester, FakeResetService(code: 'invalid-email'));

    await send(tester, 'not-an-email');

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Check your email'), findsNothing);
  });

  testWidgets('other failures stay on the form with a short message',
      (tester) async {
    await pump(tester, FakeResetService(code: 'network-request-failed'));

    await send(tester, 'kj@isufst.edu.ph');

    expect(find.text('Could not send the link. Please try again.'),
        findsOneWidget);
    expect(find.byKey(const Key('email')), findsOneWidget);
  });

  testWidgets('sending again straight away is held back for a minute',
      (tester) async {
    final service = FakeResetService();
    await pump(tester, service);
    await send(tester, 'kj@isufst.edu.ph');

    await tester.tap(find.byKey(const Key('resendReset')));
    await tester.pumpAndSettle();

    expect(service.sentTo, hasLength(1));
    expect(find.textContaining('Wait 1 minute to send another'),
        findsOneWidget);
  });

  testWidgets('the email typed on sign-in comes with the link',
      (tester) async {
    await pump(tester, FakeResetService(), initial: '/login');

    await tester.enterText(
        find.byKey(const Key('email')), 'kj@isufst.edu.ph');
    await tester.tap(find.byKey(const Key('reset')));
    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('email'))).controller!.text,
      'kj@isufst.edu.ph',
    );
  });

  testWidgets('with nothing typed on sign-in, the page opens empty',
      (tester) async {
    await pump(tester, FakeResetService(), initial: '/login');

    await tester.tap(find.byKey(const Key('reset')));
    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('email'))).controller!.text,
      isEmpty,
    );
  });

  testWidgets('Back to sign in returns to sign in', (tester) async {
    final router = await pump(tester, FakeResetService());

    await tester.tap(find.byKey(const Key('backToSignIn')));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
    expect(find.text('Sign in'), findsWidgets);
  });
}
