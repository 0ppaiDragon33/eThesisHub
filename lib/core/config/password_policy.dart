/// How strong a password looks, for guidance only — never a gate.
enum PasswordStrength { weak, fair, strong }

/// The password rules, in one testable place.
///
/// Deliberately NOT composition rules. NIST SP 800-63B §5.1.1.2 advises
/// against requiring a mix of character classes: it pushes people toward
/// `Password1!` and away from long passphrases, which are stronger and
/// easier to remember. What it recommends instead is a length minimum plus
/// a check against common, expected and context-specific passwords — which
/// is also precisely what OWASP A07 names as the failure ("permits weak or
/// well-known passwords"), rather than the absence of a symbol.
///
/// So there are two separate things here:
///
///  * [validate] is the floor, and it blocks. Length, and a refusal of
///    passwords anyone would guess first.
///  * [strengthOf] and [adviceFor] are guidance, and they never block. They
///    exist to move people above the floor voluntarily, and they reward
///    length over punctuation because that is what actually helps.
class PasswordPolicy {
  const PasswordPolicy._();

  /// Firebase Auth's own floor is 6. Eight is the project's.
  static const int minLength = 8;

  /// Passwords a guesser tries first, plus this system's own vocabulary.
  ///
  /// Matched as substrings, so `password123` and `isufst2026` are caught by
  /// `password` and `isufst`. A real deployment would check a breach corpus;
  /// this is a defensible subset for a system with no server to host one —
  /// there are no Cloud Functions on the Spark plan, so a k-anonymity call
  /// to an external breach API would have to run from the client and leak
  /// the request to a third party.
  static const List<String> _wellKnown = [
    'password', '12345678', '123456789', 'qwerty', 'letmein', 'iloveyou',
    'welcome', 'admin', 'abc123', 'monkey', 'dragon', 'sunshine',
    // Context-specific: NIST calls out "the name of the service" explicitly.
    'isufst', 'ethesishub', 'thesis', 'capstone',
  ];

  /// The blocking check. Returns an error message, or null to allow.
  ///
  /// [email] is optional so the caller can also refuse a password built from
  /// the account's own address — NIST names "the username, and derivatives
  /// thereof". Only local parts of four characters or more are considered,
  /// or a two-letter address would ban most passwords containing those two
  /// letters in sequence.
  static String? validate(String password, {String? email}) {
    if (password.isEmpty) return 'Password is required.';
    if (password.length < minLength) {
      return 'Use at least $minLength characters.';
    }

    final lower = password.toLowerCase();

    for (final weak in _wellKnown) {
      if (lower.contains(weak)) {
        return 'That password is too easy to guess. Try a phrase of a few '
            'words instead.';
      }
    }

    if (email != null && email.contains('@')) {
      final localPart = email.split('@').first.toLowerCase();
      if (localPart.length >= 4 && lower.contains(localPart)) {
        return 'Do not use your email address in your password.';
      }
    }

    return null;
  }

  /// Guidance above the floor. Length is weighted far more heavily than
  /// variety, so a passphrase always outranks a short complex string.
  static PasswordStrength strengthOf(String password) {
    final length = password.length;
    final classes = _characterClasses(password);

    // Sixteen characters is long enough that composition stops mattering;
    // below that, variety buys one step and no more. This is what keeps a
    // short complex password from ever outranking a passphrase.
    if (length >= 16) return PasswordStrength.strong;
    if (length >= 12 && classes >= 3) return PasswordStrength.strong;

    if (length >= 10) return PasswordStrength.fair;
    if (length >= minLength && classes >= 3) return PasswordStrength.fair;

    return PasswordStrength.weak;
  }

  /// One line saying what would actually improve this password, or empty
  /// when there is nothing useful left to say. Never scolds, never lists
  /// rules the password does not have to satisfy.
  static String adviceFor(String password) {
    switch (strengthOf(password)) {
      case PasswordStrength.strong:
        return '';
      case PasswordStrength.fair:
        return 'A few more words would make this much harder to guess.';
      case PasswordStrength.weak:
        return 'Longer is stronger. A phrase of three or four words beats a '
            'short password with symbols.';
    }
  }

  /// The confirmation field. Separate from [validate] so the screen can say
  /// which of the two problems it has.
  static String? validateConfirmation(String password, String confirmation) {
    if (confirmation.isEmpty) return 'Re-enter your password to confirm it.';
    if (password != confirmation) return 'The two passwords do not match.';
    return null;
  }

  static int _characterClasses(String password) {
    var classes = 0;
    if (password.contains(RegExp(r'[a-z]'))) classes++;
    if (password.contains(RegExp(r'[A-Z]'))) classes++;
    if (password.contains(RegExp(r'[0-9]'))) classes++;
    if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) classes++;
    return classes;
  }
}
