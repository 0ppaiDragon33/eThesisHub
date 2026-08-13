import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/config/email_validator.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class RegistrationController {
  RegistrationController(this._ref);

  final Ref _ref;

  /// Returns an error message, or null when registration succeeded.
  ///
  /// If the profile write fails after creating the auth account, the account
  /// is deleted to free the email for retry and prevent the UI from hanging.
  Future<String?> submit({
    required String fullName,
    required String email,
    required String password,
    String? program,
  }) async {
    if (fullName.trim().isEmpty) return 'Full name is required.';
    final emailError = EmailValidator.validateForRegistration(email);
    if (emailError != null) return emailError;
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    final auth = _ref.read(authServiceProvider);
    final users = _ref.read(userRepositoryProvider);

    try {
      // Create the auth account first
      UserCredential credential;
      try {
        credential = await auth.register(email: email, password: password);
      } on FirebaseAuthException catch (e) {
        return switch (e.code) {
          'email-already-in-use' => 'That email is already registered.',
          'weak-password' => 'Choose a stronger password.',
          _ => 'Registration failed. Please try again.',
        };
      }

      final user = credential.user!;
      final uid = user.uid;

      // Create profile and send verification; if either fails, delete the
      // just-created account to free the email and prevent the button hanging.
      try {
        await users.createStudentProfile(
          uid: uid,
          fullName: fullName,
          email: email,
          program: program,
        );
        await auth.sendEmailVerification();
        return null;
      } catch (e) {
        try {
          await user.delete();
        } catch (deleteError) {
          // Rollback delete failed; still return the original error
          return 'Could not complete registration. Please try again.';
        }
        return 'Could not complete registration. Please try again.';
      }
    } catch (e) {
      // Catch-all to ensure no exception escapes; this must never throw
      return 'Could not complete registration. Please try again.';
    }
  }
}

final registrationControllerProvider = Provider<RegistrationController>(
  (ref) => RegistrationController(ref),
);
