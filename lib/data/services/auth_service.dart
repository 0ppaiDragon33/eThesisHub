import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Forces a fresh ID token to be minted.
  ///
  /// The security rules read `request.auth.token.email_verified`, which is
  /// baked into the ID token at sign-in and cached for about an hour.
  /// `reload()` updates the local `User.emailVerified` — so the app lets a
  /// just-verified user in — but does NOT reissue the token, so Firestore
  /// keeps seeing `email_verified: false` and refuses every write the rules
  /// gate on `verified()`. Passing `true` here discards the cached token and
  /// fetches one carrying the current claims, which is the only thing that
  /// closes that window short of signing out and back in.
  Future<void> refreshIdToken() async {
    await _auth.currentUser?.getIdToken(true);
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();
}
