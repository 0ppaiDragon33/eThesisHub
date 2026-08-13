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
