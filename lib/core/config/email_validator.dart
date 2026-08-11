import 'package:ethesishub/core/config/app_config.dart';

class EmailValidator {
  static final RegExp _pattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  /// Returns an error message, or null when the address may register.
  static String? validateForRegistration(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Email is required.';
    if (!_pattern.hasMatch(trimmed)) return 'Enter a valid email address.';

    if (AppConfig.enforceInstitutionalDomain) {
      final domain = trimmed.split('@').last.toLowerCase();
      if (domain != AppConfig.institutionalDomain) {
        return 'Use your ${AppConfig.institutionalDomain} account to register.';
      }
    }
    return null;
  }
}
