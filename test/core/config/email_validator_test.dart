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

  // Domain-adjacent spoofs. The check is exact equality after lowercasing,
  // so these already fail -- but self-registration restricted to the
  // institutional domain is a claim the manuscript makes, and a claim with
  // no test behind it is a claim that quietly breaks the day someone
  // "improves" this into an endsWith or a contains.
  group('domain-adjacent spoofs are rejected when enforcement is on', () {
    // endsWith('isufst.edu.ph') would accept this.
    test('a domain that merely ENDS with the institutional one', () {
      expect(
        EmailValidator.validateForRegistration(
          'attacker@notisufst.edu.ph',
          enforceDomain: true,
        ),
        isNotNull,
      );
    });

    // startsWith / contains would accept this one.
    test('the institutional domain as a PREFIX of an attacker domain', () {
      expect(
        EmailValidator.validateForRegistration(
          'attacker@isufst.edu.ph.attacker.com',
          enforceDomain: true,
        ),
        isNotNull,
      );
    });

    // contains() would accept this: the real domain buried mid-string.
    test('the institutional domain embedded in the middle', () {
      expect(
        EmailValidator.validateForRegistration(
          'attacker@mail.isufst.edu.ph.evil.net',
          enforceDomain: true,
        ),
        isNotNull,
      );
    });

    // A subdomain is NOT the institution's domain. Strict by design: if
    // ISUFST ever issues mail.isufst.edu.ph addresses this test is the
    // place that says so out loud rather than a silent behaviour change.
    test('a subdomain of the institutional domain', () {
      expect(
        EmailValidator.validateForRegistration(
          'someone@mail.isufst.edu.ph',
          enforceDomain: true,
        ),
        isNotNull,
      );
    });
  });
}
