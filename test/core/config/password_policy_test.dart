import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/config/password_policy.dart';

void main() {
  group('the hard floor', () {
    test('rejects anything shorter than the minimum', () {
      expect(PasswordPolicy.validate('short1'), isNotNull);
      expect(PasswordPolicy.validate('1234567'), isNotNull);
    });

    test('accepts a long passphrase with no symbols or digits at all', () {
      // The point of the NIST-style floor: length is the control, not
      // composition. A rule demanding a symbol here would reject a password
      // that is stronger than anything it would accept.
      expect(
        PasswordPolicy.validate('correct horse battery staple'),
        isNull,
      );
    });

    test('rejects well-known passwords regardless of length', () {
      // OWASP A07 names "permits weak or well-known passwords" as the
      // failure. This is that control.
      for (final weak in ['password', 'password123', '12345678', 'qwertyui']) {
        expect(PasswordPolicy.validate(weak), isNotNull,
            reason: '$weak should be refused');
      }
    });

    test('rejects a password built from the service name', () {
      for (final weak in ['isufst2026', 'ethesishub1', 'thesis1234']) {
        expect(PasswordPolicy.validate(weak), isNotNull,
            reason: '$weak should be refused');
      }
    });

    test('rejects a password containing the user own email name', () {
      // NIST calls out "the username, and derivatives thereof" explicitly.
      expect(
        PasswordPolicy.validate('kjvargas2026', email: 'kjvargas@isufst.edu.ph'),
        isNotNull,
      );
      // ...but the same password is fine for a different person, which is
      // what proves the check is contextual and not just another blocklist
      // entry.
      expect(
        PasswordPolicy.validate('kjvargas2026', email: 'someone@isufst.edu.ph'),
        isNull,
      );
    });

    test('ignores case when matching a known-weak password', () {
      expect(PasswordPolicy.validate('PassWord'), isNotNull);
    });

    test('does not reject a short email name appearing incidentally', () {
      // A two- or three-letter local part would otherwise ban most
      // passwords containing those letters in sequence.
      expect(
        PasswordPolicy.validate('a-genuinely-long-passphrase', email: 'ab@x.ph'),
        isNull,
      );
    });
  });

  group('the strength meter', () {
    test('length dominates, per NIST', () {
      // Eight characters using every character class reaches no better than
      // fair — composition cannot buy its way to strong...
      expect(PasswordPolicy.strengthOf('Ab1!xyzq'), PasswordStrength.fair);
      // ...while a long all-lowercase phrase with no digit or symbol in it
      // is strong outright.
      expect(PasswordPolicy.strengthOf('a much longer passphrase here'),
          PasswordStrength.strong);
    });

    test('a long passphrase beats a short complex password', () {
      // If this ever inverts, the meter has drifted back to rewarding
      // composition over length and is teaching the wrong habit.
      final passphrase = PasswordPolicy.strengthOf('four word pass phrase');
      final complex = PasswordPolicy.strengthOf('Xy7!aB2#');
      expect(passphrase.index, greaterThan(complex.index));
    });

    test('variety still helps at a middling length', () {
      expect(PasswordPolicy.strengthOf('abcdefghijkl'),
          PasswordStrength.fair);
      expect(PasswordPolicy.strengthOf('Abcdefgh1jkl!'),
          PasswordStrength.strong);
    });

    test('advice says what would actually improve this password', () {
      expect(
          PasswordPolicy.adviceFor('abcdefgh').toLowerCase(), contains('longer'));
      // Nothing useful left to say about a genuinely strong one.
      expect(PasswordPolicy.adviceFor('a much longer passphrase here'), isEmpty);
    });
  });

  group('confirmation', () {
    test('mismatched confirmation is refused', () {
      expect(PasswordPolicy.validateConfirmation('abc', 'abd'), isNotNull);
    });

    test('matching confirmation passes', () {
      expect(PasswordPolicy.validateConfirmation('abc', 'abc'), isNull);
    });

    test('an empty confirmation is refused rather than silently accepted', () {
      expect(PasswordPolicy.validateConfirmation('abcdefgh', ''), isNotNull);
    });
  });
}
