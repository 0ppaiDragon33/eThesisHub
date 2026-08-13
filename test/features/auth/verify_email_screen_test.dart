import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Records calls to promoteFromInvite.
class RecordingUserRepository extends UserRepository {
  RecordingUserRepository(super._db);

  int promoteFromInviteCallCount = 0;
  String? lastPromotedUid;
  String? lastPromotedEmail;

  @override
  Future<UserRole?> promoteFromInvite({
    required String uid,
    required String email,
  }) async {
    promoteFromInviteCallCount++;
    lastPromotedUid = uid;
    lastPromotedEmail = email;
    return await super.promoteFromInvite(uid: uid, email: email);
  }
}

/// Throws non-permission-denied error from promoteFromInvite.
class FailingPromoteUserRepository extends UserRepository {
  FailingPromoteUserRepository(super._db);

  @override
  Future<UserRole?> promoteFromInvite({
    required String uid,
    required String email,
  }) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'internal',
      message: 'Internal error during promote.',
    );
  }
}

/// Custom auth service that fails on sendEmailVerification.
class FailingEmailService extends AuthService {
  FailingEmailService(MockFirebaseAuth mockAuth) : super(mockAuth);

  @override
  Future<void> sendEmailVerification() async {
    throw FirebaseAuthException(code: 'too-many-requests');
  }
}

/// Custom auth service that fails on signOut.
class FailingSignOutService extends AuthService {
  FailingSignOutService(MockFirebaseAuth mockAuth) : super(mockAuth);

  @override
  Future<void> signOut() async {
    throw FirebaseAuthException(code: 'unknown');
  }
}

void main() {
  testWidgets('verified path applies the invite', (tester) async {
    final db = FakeFirebaseFirestore();
    final repo = RecordingUserRepository(db);
    await repo.createStudentProfile(
      uid: 'uid-faculty',
      fullName: 'Dr. Faculty',
      email: 'faculty@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'faculty@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator',
    );

    final mockAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'uid-faculty',
        email: 'faculty@isufst.edu.ph',
        isEmailVerified: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          userRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: VerifyEmailScreen()),
      ),
    );

    // Initially, promoteFromInvite should not have been called
    expect(repo.promoteFromInviteCallCount, 0);

    // Tap continue button
    await tester.tap(find.byKey(const Key('reload')));
    await tester.pumpAndSettle();

    // Should have called promoteFromInvite with correct uid and email
    expect(repo.promoteFromInviteCallCount, 1,
        reason: 'promoteFromInvite should be called when email is verified');
    expect(repo.lastPromotedUid, 'uid-faculty');
    expect(repo.lastPromotedEmail, 'faculty@isufst.edu.ph');

    // Confirmation message should be shown
    expect(find.textContaining('verified! You can now proceed'), findsOneWidget);
  });

  testWidgets('not-verified path skips promotion', (tester) async {
    final db = FakeFirebaseFirestore();
    final repo = RecordingUserRepository(db);

    final mockAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'uid-user',
        email: 'user@isufst.edu.ph',
        isEmailVerified: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          userRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: VerifyEmailScreen()),
      ),
    );

    // Tap continue button
    await tester.tap(find.byKey(const Key('reload')));
    await tester.pumpAndSettle();

    // Should show "not confirmed yet" message
    expect(find.textContaining('inbox'), findsOneWidget);

    // promoteFromInvite should NOT have been called
    expect(repo.promoteFromInviteCallCount, 0,
        reason: 'promoteFromInvite should not be called for unverified email');
  });

  testWidgets('promotion failure surfaces error message', (tester) async {
    final db = FakeFirebaseFirestore();

    final mockAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'uid-faculty',
        email: 'faculty@isufst.edu.ph',
        isEmailVerified: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          userRepositoryProvider
              .overrideWithValue(FailingPromoteUserRepository(db)),
        ],
        child: const MaterialApp(home: VerifyEmailScreen()),
      ),
    );

    // Tap continue button
    await tester.tap(find.byKey(const Key('reload')));
    await tester.pumpAndSettle();

    // Should show error message, not crash
    expect(find.textContaining('failed'), findsOneWidget);
  });

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
