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

  test('rejects a non-institutional domain while enforcement is on', () {
    final error = EmailValidator.validateForRegistration('someone@gmail.com');
    expect(error, isNotNull);
    expect(error, contains('isufst.edu.ph'));
  });

  test('is case-insensitive about the domain', () {
    expect(
      EmailValidator.validateForRegistration('Someone@ISUFST.EDU.PH'),
      isNull,
    );
  });
}
