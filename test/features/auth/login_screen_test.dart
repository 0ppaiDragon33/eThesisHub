import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Rejects every sign-in. Subclassing AuthService keeps this test independent
/// of firebase_auth_mocks' exception-injection API.
class FailingAuthService extends AuthService {
  FailingAuthService() : super(MockFirebaseAuth());

  @override
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    throw FirebaseAuthException(code: 'wrong-password');
  }
}

/// Throws a Firestore error (permission-denied) when promoting an invite.
class PermissionDeniedUserRepository extends UserRepository {
  PermissionDeniedUserRepository(super._db);

  @override
  Future<UserRole?> promoteFromInvite({
    required String uid,
    required String email,
  }) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}

/// Throws a non-permission-denied Firestore error when promoting an invite.
class FirestoreErrorUserRepository extends UserRepository {
  FirestoreErrorUserRepository(super._db);

  @override
  Future<UserRole?> promoteFromInvite({
    required String uid,
    required String email,
  }) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'internal',
      message: 'Internal error.',
    );
  }
}

/// Password reset always fails.
class FailingAuthServiceReset extends AuthService {
  FailingAuthServiceReset() : super(MockFirebaseAuth());

  @override
  Future<void> sendPasswordReset(String email) async {
    throw FirebaseAuthException(code: 'user-not-found');
  }
}

void main() {
  testWidgets('shows an error when credentials are rejected', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
          authServiceProvider.overrideWithValue(FailingAuthService()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('email')), 'kjvargas@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Incorrect'), findsOneWidget);
  });

  testWidgets('promotes an invited user on first successful login',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final repo = UserRepository(db);
    await repo.createStudentProfile(
      uid: 'uid-1',
      fullName: 'Dr. Reyes',
      email: 'reyes@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'reyes@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(
              mockUser: MockUser(
                uid: 'uid-1',
                email: 'reyes@isufst.edu.ph',
                isEmailVerified: true,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('email')), 'reyes@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect((await repo.fetchUser('uid-1'))!.role, UserRole.faculty);
  });

  testWidgets('reset requires an email address first', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key('reset')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter your email first'), findsOneWidget);
  });

  testWidgets('handles permission-denied from unverified invite read',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final repo = UserRepository(db);
    await repo.createStudentProfile(
      uid: 'uid-1',
      fullName: 'Dr. Unverified',
      email: 'unverified@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'unverified@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(
              mockUser: MockUser(
                uid: 'uid-1',
                email: 'unverified@isufst.edu.ph',
                isEmailVerified: false,
              ),
            ),
          ),
          userRepositoryProvider
              .overrideWithValue(PermissionDeniedUserRepository(db)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('email')), 'unverified@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // Sign-in should succeed with no error visible
    expect(find.textContaining('Incorrect'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
    // Button should be re-enabled
    expect(find.byKey(const Key('submit')).evaluate().single.renderObject,
        isA<RenderObject>());
  });

  testWidgets('shows error when invite read throws non-permission-denied error',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final repo = UserRepository(db);
    await repo.createStudentProfile(
      uid: 'uid-1',
      fullName: 'Dr. Reyes',
      email: 'reyes@isufst.edu.ph',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(
              mockUser: MockUser(
                uid: 'uid-1',
                email: 'reyes@isufst.edu.ph',
                isEmailVerified: true,
              ),
            ),
          ),
          userRepositoryProvider
              .overrideWithValue(FirestoreErrorUserRepository(db)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('email')), 'reyes@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // Should show error message
    expect(find.textContaining('failed'), findsOneWidget);
  });

  testWidgets('password reset shows error on failure', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
          authServiceProvider.overrideWithValue(FailingAuthServiceReset()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('email')), 'unknown@isufst.edu.ph');
    await tester.tap(find.byKey(const Key('reset')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to send'), findsOneWidget);
  });
}
