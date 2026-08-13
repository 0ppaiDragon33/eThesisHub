import 'package:ethesishub/data/models/user_role.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    required this.active,
    required this.createdAt,
    this.college,
    this.program,
    this.specialization,
    this.createdBy,
  });

  final String uid;
  final String fullName;
  final String email;
  final UserRole role;
  final bool active;
  final DateTime createdAt;
  final String? college;
  final String? program;
  final String? specialization;
  final String? createdBy;

  /// True for every role that may hold a thesis position or approve work.
  bool get isFaculty => role != UserRole.student;

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      fullName: map['fullName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: UserRole.tryParse(map['role'] as String?) ?? UserRole.student,
      college: map['college'] as String?,
      program: map['program'] as String?,
      specialization: map['specialization'] as String?,
      active: map['active'] as bool? ?? true,
      createdAt: map['createdAt'] as DateTime? ?? DateTime.now().toUtc(),
      createdBy: map['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'email': email,
        'role': role.value,
        'college': college,
        'program': program,
        'specialization': specialization,
        'active': active,
        'createdAt': createdAt,
        'createdBy': createdBy,
      };
}
