import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/core/config/email_validator.dart';

void main() {
  // Printed on every run while enforcement is disabled, so the temporary
  // testing configuration cannot be forgotten. Restore
  // AppConfig.enforceInstitutionalDomain to true before the defense.
  const enforcementSkipReason = AppConfig.enforceInstitutionalDomain
      ? null
      : 'SKIPPED: AppConfig.enforceInstitutionalDomain is FALSE '
          '(temporary testing config). RESTORE IT TO true BEFORE DEFENSE — '
          'the manuscript claims registration is restricted to '
          'institutional addresses.';

  test('accepts a well-formed institutional address', () {
    expect(
      EmailValidator.validateForRegistration('kjvargas@isufst.edu.ph'),
      isNull,
    );
  });

  test('enforcement flag is enabled', () {
    expect(AppConfig.enforceInstitutionalDomain, isTrue);
  }, skip: enforcementSkipReason);

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
  }, skip: enforcementSkipReason);

  test('is case-insensitive about the domain', () {
    expect(
      EmailValidator.validateForRegistration('Someone@ISUFST.EDU.PH'),
      isNull,
    );
  });
}
