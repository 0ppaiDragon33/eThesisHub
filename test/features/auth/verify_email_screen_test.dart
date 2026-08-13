import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Custom auth service that fails on sendEmailVerification.
class FailingEmailService extends AuthService {
  final MockFirebaseAuth _mockAuth;

  FailingEmailService(this._mockAuth) : super(_mockAuth);

  @override
  Future<void> sendEmailVerification() async {
    throw FirebaseAuthException(code: 'too-many-requests');
  }
}

/// Custom auth service that fails on signOut.
class FailingSignOutService extends AuthService {
  final MockFirebaseAuth _mockAuth;

  FailingSignOutService(this._mockAuth) : super(_mockAuth);

  @override
  Future<void> signOut() async {
    throw FirebaseAuthException(code: 'unknown');
  }
}

void main() {
  testWidgets('resend button shows error on failure', (tester) async {
    final mockAuth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'uid-1',
        email: 'user@isufst.edu.ph',
        isEmailVerified: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          authServiceProvider.overrideWithValue(FailingEmailService(mockAuth)),
        ],
        child: const MaterialApp(home: VerifyEmailScreen()),
      ),
    );

    // Tap resend button
    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    // Should show error in snackbar
    expect(find.textContaining('Failed to resend'), findsOneWidget);
  });

  testWidgets('signout button shows error on failure', (tester) async {
    final mockAuth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'uid-1',
        email: 'user@isufst.edu.ph',
        isEmailVerified: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          authServiceProvider.overrideWithValue(FailingSignOutService(mockAuth)),
        ],
        child: const MaterialApp(home: VerifyEmailScreen()),
      ),
    );

    // Tap signout button
    await tester.tap(find.byKey(const Key('signout')));
    await tester.pumpAndSettle();

    // Should show error in snackbar
    expect(find.textContaining('Failed to sign out'), findsOneWidget);
  });
}
