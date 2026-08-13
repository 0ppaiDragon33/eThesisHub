import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/auth_service.dart';

void main() {
  test('register creates a signed-in user', () async {
    final auth = MockFirebaseAuth();
    final service = AuthService(auth);

    final credential = await service.register(
      email: 'kjvargas@isufst.edu.ph',
      password: 'Str0ngPass!',
    );

    expect(credential.user, isNotNull);
    expect(service.currentUser, isNotNull);
  });

  test('signIn returns a credential for an existing user', () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'uid-1',
        email: 'kjvargas@isufst.edu.ph',
        isEmailVerified: true,
      ),
    );
    final service = AuthService(auth);

    final credential = await service.signIn(
      email: 'kjvargas@isufst.edu.ph',
      password: 'Str0ngPass!',
    );

    expect(credential.user!.uid, 'uid-1');
  });

  test('signOut clears the current user', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final service = AuthService(auth);

    expect(service.currentUser, isNotNull);
    await service.signOut();
    expect(service.currentUser, isNull);
  });

  test('authStateChanges emits on sign out', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final service = AuthService(auth);

    final expectation = expectLater(
      service.authStateChanges(),
      emitsThrough(isNull),
    );
    await service.signOut();
    await expectation;
  });

  test('sendPasswordReset delegates without throwing', () async {
    final auth = MockFirebaseAuth();
    final service = AuthService(auth);

    expect(
      service.sendPasswordReset('kjvargas@isufst.edu.ph'),
      completes,
    );
  });

  test('sendEmailVerification succeeds with a signed-in user', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'uid-1',
        email: 'kjvargas@isufst.edu.ph',
        isEmailVerified: false,
      ),
    );
    final service = AuthService(auth);

    expect(service.sendEmailVerification(), completes);
  });
}
