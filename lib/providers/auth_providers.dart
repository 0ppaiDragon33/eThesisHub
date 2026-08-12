import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/data/services/auth_service.dart';

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(firebaseAuthProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(firestoreProvider)),
);

final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return _authStateStream(authService);
});

Stream<User?> _authStateStream(AuthService authService) async* {
  // Emit current state immediately
  yield authService.currentUser;
  // Then emit any changes
  yield* authService.authStateChanges();
}

/// The signed-in user's profile, or null when signed out.
final currentUserProvider = StreamProvider<AppUser?>((ref) async* {
  final authState = await ref.watch(authStateProvider.future);
  if (authState == null) {
    yield null;
  } else {
    yield* ref.watch(userRepositoryProvider).watchUser(authState.uid);
  }
});
