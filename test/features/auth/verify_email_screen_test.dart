import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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

/// Throws a non-permission-denied error from the directory write, to prove
/// it can't strand a verified user on this screen.
class FailingFacultyDirectoryRepository extends FacultyDirectoryRepository {
  FailingFacultyDirectoryRepository(super.db);

  @override
  Future<void> upsertOwnEntry(AppUser user) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'Simulated transient Firestore outage.',
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

/// A User whose reload() flips an externally-owned flag rather than mutating
/// itself, so that (like real FirebaseAuth) the *same* User object returned
/// before reload() stays stale, while a freshly-read `currentUser` reflects
/// the change. `props` includes the verified flag so distinct instances with
/// different verification states are never treated as Equatable-equal.
// ignore: must_be_immutable
class _TrackedUser extends MockUser {
  _TrackedUser({
    required super.uid,
    required super.email,
    required bool verified,
    this.onReload,
  })  : _verified = verified,
        super(isEmailVerified: verified);

  final bool _verified;
  final VoidCallback? onReload;

  @override
  bool get emailVerified => _verified;

  @override
  List<Object?> get props => [...super.props, _verified];

  @override
  Future<void> reload() async {
    onReload?.call();
  }
}

/// Simulates real FirebaseAuth's authStateChanges(): re-subscribing (as
/// `ref.invalidate(authStateProvider)` causes) yields a fresh User reflecting
/// current state, but reload() alone never pushes a new stream event.
class _FlippableAuthService extends AuthService {
  _FlippableAuthService(super.auth, this._uid, this._email);

  final String _uid;
  final String _email;
  bool _verified = false;

  @override
  User? get currentUser => _TrackedUser(
        uid: _uid,
        email: _email,
        verified: _verified,
        onReload: () => _verified = true,
      );

  @override
  Stream<User?> authStateChanges() => Stream.value(currentUser);
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

  testWidgets(
      'continuing after verification navigates to the dashboard '
      '(fails without invalidating authStateProvider)', (tester) async {
    const uid = 'uid-nav';
    const email = 'student@isufst.edu.ph';

    final db = FakeFirebaseFirestore();
    await UserRepository(db).createStudentProfile(
      uid: uid,
      fullName: 'Nav Student',
      email: email,
    );

    final mockAuth = MockFirebaseAuth();
    final authService = _FlippableAuthService(mockAuth, uid, email);

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authServiceProvider.overrideWithValue(authService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Starts unverified, so the router lands on the verify-email screen.
    expect(find.text('Verify your email'), findsOneWidget);

    // Tap continue: reload() flips the service's internal verified flag,
    // then the screen must invalidate authStateProvider so the router picks
    // up the change and redirects onward.
    await tester.tap(find.byKey(const Key('reload')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('studentDashboard')), findsOneWidget,
        reason: 'without invalidating authStateProvider, the router never '
            're-evaluates its redirect and the user is stuck on '
            '/verify-email');
    expect(find.text('Verify your email'), findsNothing);
  });

  testWidgets(
      'a non-permission-denied directory write failure does not strand a '
      'verified user on this screen', (tester) async {
    const uid = 'uid-nav-2';
    const email = 'student2@isufst.edu.ph';

    final db = FakeFirebaseFirestore();
    await UserRepository(db).createStudentProfile(
      uid: uid,
      fullName: 'Nav Student Two',
      email: email,
    );

    final mockAuth = MockFirebaseAuth();
    final authService = _FlippableAuthService(mockAuth, uid, email);

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authServiceProvider.overrideWithValue(authService),
        facultyDirectoryRepositoryProvider
            .overrideWithValue(FailingFacultyDirectoryRepository(db)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Starts unverified, so the router lands on the verify-email screen.
    expect(find.text('Verify your email'), findsOneWidget);

    // Tap continue: the directory write throws 'unavailable'. That must be
    // absorbed the same way the audit-log failure is absorbed, so
    // ref.invalidate(authStateProvider) still runs and the router still
    // redirects onward — the user must not see "Verification failed."
    await tester.tap(find.byKey(const Key('reload')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('studentDashboard')), findsOneWidget,
        reason: 'a non-permission-denied directory write failure must not '
            'skip the authStateProvider invalidate and strand the user on '
            '/verify-email');
    expect(find.textContaining('Verification failed'), findsNothing);
  });
}
