enum UserRole {
  student,
  faculty,
  coordinator,
  dean;

  String get value => name;

  static UserRole? tryParse(String? raw) {
    if (raw == null) return null;
    for (final role in UserRole.values) {
      if (role.name == raw) return role;
    }
    return null;
  }
}

/// The name a role is shown under. Display only — what the app does with a
/// role is decided elsewhere and never defaulted from this.
String roleLabel(UserRole role) => switch (role) {
      UserRole.student => 'Student researcher',
      UserRole.faculty => 'Faculty',
      UserRole.coordinator => 'Research Coordinator',
      UserRole.dean => 'Dean',
    };
