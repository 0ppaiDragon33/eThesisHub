import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/config/email_validator.dart';

void main() {
  test('accepts a well-formed institutional address', () {
    expect(
      EmailValidator.validateForRegistration('kjvargas@isufst.edu.ph'),
      isNull,
    );
  });

  test('rejects an empty address', () {
    expect(EmailValidator.validateForRegistration(''), isNotNull);
  });

  test('rejects a malformed address', () {
    expect(EmailValidator.validateForRegistration('not-an-email'), isNotNull);
  });

  // Both states are asserted explicitly rather than through the ambient
  // flag. The flag is currently relaxed so the five roles can be tested from
  // ordinary mail accounts, and a test that just followed it would quietly
  // stop proving the restriction works at exactly the moment it is off.

  test('rejects a non-institutional domain when enforcement is on', () {
    final error = EmailValidator.validateForRegistration(
      'someone@gmail.com',
      enforceDomain: true,
    );
    expect(error, isNotNull);
    expect(error, contains('isufst.edu.ph'));
  });

  test('accepts any well-formed address when enforcement is off', () {
    expect(
      EmailValidator.validateForRegistration(
        'someone@gmail.com',
        enforceDomain: false,
      ),
      isNull,
    );
  });

  test('still rejects a malformed address when enforcement is off', () {
    // Relaxing the domain must not relax what counts as an email at all.
    expect(
      EmailValidator.validateForRegistration(
        'not-an-email',
        enforceDomain: false,
      ),
      isNotNull,
    );
  });

  test('is case-insensitive about the domain', () {
    expect(
      EmailValidator.validateForRegistration(
        'Someone@ISUFST.EDU.PH',
        enforceDomain: true,
      ),
      isNull,
    );
  });
}
