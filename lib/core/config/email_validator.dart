import 'package:ethesishub/core/config/app_config.dart';

class EmailValidator {
  static final RegExp _pattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  /// Returns an error message, or null when the address may register.
  ///
  /// [enforceDomain] defaults to [AppConfig.enforceInstitutionalDomain] and
  /// exists so tests can exercise both states regardless of how the flag is
  /// currently set. Without it, relaxing the flag for testing would silently
  /// delete the coverage that proves the restriction works — and that
  /// restriction is the whole self-registration defence the manuscript
  /// describes.
  static String? validateForRegistration(String email, {bool? enforceDomain}) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Email is required.';
    if (!_pattern.hasMatch(trimmed)) return 'Enter a valid email address.';

    if (enforceDomain ?? AppConfig.enforceInstitutionalDomain) {
      final domain = trimmed.split('@').last.toLowerCase();
      if (domain != AppConfig.institutionalDomain) {
        return 'Use your ${AppConfig.institutionalDomain} account to register.';
      }
    }
    return null;
  }
}
