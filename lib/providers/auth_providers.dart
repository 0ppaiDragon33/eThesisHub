import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/faculty_invite.dart';
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

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// Every faculty invite, open and consumed. Only coordinators may read this —
/// the security rules deny `list` to everyone else — so the stream surfaces
/// an error rather than an empty list for any other role, and the screen says
/// so instead of implying there are none.
final facultyInvitesProvider = StreamProvider<List<FacultyInvite>>(
  (ref) => ref.watch(userRepositoryProvider).watchInvites(),
);

/// The signed-in user's profile, or null when signed out.
///
/// Awaits the auth state rather than reading `.value`, because `.value` is
/// null both while auth is loading and when the user is signed out — reading
/// it directly would report "signed out" during startup and bounce users to
/// the login screen. Awaiting keeps the provider in a loading state until
/// auth actually settles.
final currentUserProvider = StreamProvider<AppUser?>((ref) async* {
  final authState = await ref.watch(authStateProvider.future);
  if (authState == null) {
    yield null;
    return;
  }
  yield* ref.watch(userRepositoryProvider).watchUser(authState.uid);
});
