import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

void main() {
  test('currentUserProvider resolves the profile of the signed-in user',
      () async {
    final db = FakeFirebaseFirestore();
    await UserRepository(db).createStudentProfile(
      uid: 'uid-1',
      fullName: 'Karl Joshua P. Vargas',
      email: 'kjvargas@isufst.edu.ph',
    );

    final mockUser = MockUser(
      uid: 'uid-1',
      email: 'kjvargas@isufst.edu.ph',
      isEmailVerified: true,
    );

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(
          MockFirebaseAuth(signedIn: true, mockUser: mockUser),
        ),
        authStateProvider.overrideWith((ref) => Stream.value(mockUser as User?)),
      ],
    );
    addTearDown(container.dispose);

    final user = await container.read(currentUserProvider.future);
    expect(user, isNotNull);
    expect(user!.role, UserRole.student);
  });

  test('currentUserProvider is null when signed out', () async {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
        authStateProvider.overrideWith((ref) => Stream.value(null as User?)),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(currentUserProvider.future), isNull);
  });
}
