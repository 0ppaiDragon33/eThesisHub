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

/// The signed-in uid alone, and nothing else about the user.
///
/// Every stream whose permission depends on WHO is asking must depend on
/// this. A plain [StreamProvider] is built once and lives for the whole life
/// of the container, so a Firestore listener denied under one account stayed
/// in `AsyncError` forever: signing out and back in as somebody else did not
/// rebuild it, and the only thing that ever cleared the refusal was reloading
/// the page. Watching the uid rather than the whole auth state means a token
/// refresh -- which fires `authStateChanges` without changing who you are --
/// does not tear every listener down and build it again for nothing.
final signedInUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.uid,
);

/// Every faculty invite, open and consumed. Only coordinators may read this —
/// the security rules deny `list` to everyone else — so the stream surfaces
/// an error rather than an empty list for any other role, and the screen says
/// so instead of implying there are none.
final facultyInvitesProvider = StreamProvider<List<FacultyInvite>>(
  (ref) {
    // Rebuilt on a change of user: see [signedInUidProvider].
    ref.watch(signedInUidProvider);
    return ref.watch(userRepositoryProvider).watchInvites();
  },
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
