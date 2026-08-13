import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';

void main() {
  test('value returns the stored string form', () {
    expect(UserRole.coordinator.value, 'coordinator');
  });

  test('tryParse maps known strings', () {
    expect(UserRole.tryParse('dean'), UserRole.dean);
    expect(UserRole.tryParse('student'), UserRole.student);
  });

  test('tryParse returns null for unknown or missing values', () {
    expect(UserRole.tryParse('administrator'), isNull);
    expect(UserRole.tryParse(null), isNull);
  });
}
