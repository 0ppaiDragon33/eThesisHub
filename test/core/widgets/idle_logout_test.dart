import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/widgets/idle_logout.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Reports a fixed auth state and counts sign-outs, so the timer's effect is
/// observable without a live Firebase.
class _FakeAuth extends AuthService {
  _FakeAuth(this._user) : super(MockFirebaseAuth());

  final User? _user;
  int signOutCount = 0;

  @override
  Stream<User?> authStateChanges() => Stream.value(_user);

  @override
  Future<void> signOut() async => signOutCount++;
}

void main() {
  const timeout = Duration(seconds: 10);

  Future<_FakeAuth> pump(WidgetTester tester, {required bool signedIn}) async {
    final auth = _FakeAuth(
      signedIn
          ? MockUser(uid: 'u', email: 'u@isufst.edu.ph', isEmailVerified: true)
          : null,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)],
      child: const MaterialApp(
        home: IdleLogout(
          timeout: timeout,
          child: Scaffold(body: Center(child: Text('desk'))),
        ),
      ),
    ));
    await tester.pump();
    return auth;
  }

  testWidgets('signs out after the timeout when signed in', (tester) async {
    final auth = await pump(tester, signedIn: true);

    expect(auth.signOutCount, 0);
    await tester.pump(timeout + const Duration(seconds: 1));
    expect(auth.signOutCount, 1);
  });

  testWidgets('activity resets the clock', (tester) async {
    final auth = await pump(tester, signedIn: true);

    // Most of the way there...
    await tester.pump(const Duration(seconds: 7));
    // ...then a tap, which re-arms the full timeout.
    await tester.tap(find.text('desk'));
    await tester.pump(const Duration(seconds: 7));
    expect(auth.signOutCount, 0, reason: 'the tap pushed the deadline back');

    // Now let it run out with no activity.
    await tester.pump(timeout + const Duration(seconds: 1));
    expect(auth.signOutCount, 1);
  });

  testWidgets('a signed-out reader is not signed out again', (tester) async {
    final auth = await pump(tester, signedIn: false);

    await tester.pump(timeout + const Duration(seconds: 1));
    expect(auth.signOutCount, 0);
  });
}
