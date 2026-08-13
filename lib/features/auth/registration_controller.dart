import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/config/email_validator.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class RegistrationController {
  RegistrationController(this._ref);

  final Ref _ref;

  /// Returns an error message, or null when registration succeeded.
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
      final credential = await auth.register(email: email, password: password);
      final uid = credential.user!.uid;

      await users.createStudentProfile(
        uid: uid,
        fullName: fullName,
        email: email,
        program: program,
      );
      await auth.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'email-already-in-use' => 'That email is already registered.',
        'weak-password' => 'Choose a stronger password.',
        _ => 'Registration failed. Please try again.',
      };
    }
  }
}

final registrationControllerProvider = Provider<RegistrationController>(
  (ref) => RegistrationController(ref),
);
