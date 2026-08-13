import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 12);

  test('fromMap reads all fields', () {
    final user = AppUser.fromMap('uid-1', {
      'fullName': 'Karl Joshua P. Vargas',
      'email': 'kjvargas@isufst.edu.ph',
      'role': 'student',
      'college': 'CICT',
      'program': 'BSIT',
      'specialization': null,
      'active': true,
      'createdAt': createdAt,
      'createdBy': null,
    });

    expect(user.uid, 'uid-1');
    expect(user.fullName, 'Karl Joshua P. Vargas');
    expect(user.role, UserRole.student);
    expect(user.program, 'BSIT');
    expect(user.active, isTrue);
  });

  test('fromMap defaults an unknown role to student', () {
    final user = AppUser.fromMap('uid-2', {
      'fullName': 'Someone',
      'email': 'someone@isufst.edu.ph',
      'role': 'superadmin',
      'active': true,
      'createdAt': createdAt,
    });

    expect(user.role, UserRole.student);
  });

  test('toMap round-trips through fromMap', () {
    final original = AppUser(
      uid: 'uid-3',
      fullName: 'Dr. Reyes',
      email: 'reyes@isufst.edu.ph',
      role: UserRole.faculty,
      college: 'CICT',
      active: true,
      createdAt: createdAt,
    );

    final restored = AppUser.fromMap('uid-3', original.toMap());
    expect(restored.email, original.email);
    expect(restored.role, UserRole.faculty);
    expect(restored.college, 'CICT');
  });

  test('isFaculty is true for faculty, coordinator and dean', () {
    AppUser build(UserRole role) => AppUser(
          uid: 'u',
          fullName: 'n',
          email: 'e@isufst.edu.ph',
          role: role,
          active: true,
          createdAt: createdAt,
        );

    expect(build(UserRole.student).isFaculty, isFalse);
    expect(build(UserRole.faculty).isFaculty, isTrue);
    expect(build(UserRole.coordinator).isFaculty, isTrue);
    expect(build(UserRole.dean).isFaculty, isTrue);
  });
}
