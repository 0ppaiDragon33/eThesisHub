class FacultyDirectoryEntry {
  const FacultyDirectoryEntry({
    required this.uid,
    required this.fullName,
    required this.role,
    this.college,
    this.specialization,
  });

  final String uid;
  final String fullName;
  final String role;
  final String? college;
  final String? specialization;

  /// Shown under the name in the picker.
  String get subtitle => [college, specialization]
      .where((s) => s != null && s.isNotEmpty)
      .join(' · ');

  factory FacultyDirectoryEntry.fromMap(String uid, Map<String, dynamic> map) {
    return FacultyDirectoryEntry(
      uid: uid,
      fullName: map['fullName'] as String? ?? '',
      role: map['role'] as String? ?? 'faculty',
      college: map['college'] as String?,
      specialization: map['specialization'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'role': role,
        'college': college,
        'specialization': specialization,
      };
}
