import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/features/auth/registration_controller.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Fake credential.user that records whether delete() was called.
// ignore: must_be_immutable
class _TrackedDeleteUser extends MockUser {
  _TrackedDeleteUser({required super.uid, required super.email});

  bool deleteCalled = false;

  @override
  Future<void> delete() async {
    deleteCalled = true;
  }
}

class _FakeUserCredential implements UserCredential {
  _FakeUserCredential(this.user);

  @override
  final User user;

  @override
  AdditionalUserInfo? get additionalUserInfo => null;

  @override
  AuthCredential? get credential => null;
}

/// The profile write succeeds, but sendEmailVerification always throws
/// (simulating a routine too-many-requests error).
class _ProfileOkVerifyFailsAuthService extends AuthService {
  _ProfileOkVerifyFailsAuthService(super.auth, this.trackedUser);

  final _TrackedDeleteUser trackedUser;

  @override
  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    return _FakeUserCredential(trackedUser);
  }

  @override
  Future<void> sendEmailVerification() async {
    throw FirebaseAuthException(code: 'too-many-requests');
  }
}

void main() {
  test(
      'profile write succeeds but sendEmailVerification fails: '
      'account is kept and a non-fatal message is returned', () async {
    final db = FakeFirebaseFirestore();
    final trackedUser =
        _TrackedDeleteUser(uid: 'uid-1', email: 'kjvargas@isufst.edu.ph');
    final mockAuth = MockFirebaseAuth();

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authServiceProvider.overrideWithValue(
          _ProfileOkVerifyFailsAuthService(mockAuth, trackedUser),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(registrationControllerProvider).submit(
          fullName: 'Karl Vargas',
          email: 'kjvargas@isufst.edu.ph',
          password: 'Str0ngPass!',
        );

    // submit() must not fail fatally: null or a non-fatal message is fine,
    // but the tautological "Could not complete registration" rollback
    // message would indicate the account was destroyed.
    expect(result, isNot(contains('Could not complete registration')));

    // The profile write must have succeeded.
    final profile = await db.collection('users').doc('uid-1').get();
    expect(profile.exists, isTrue);
    expect(profile.data()!['role'], 'student');

    // The account must NOT have been rolled back.
    expect(trackedUser.deleteCalled, isFalse);
  });
}
