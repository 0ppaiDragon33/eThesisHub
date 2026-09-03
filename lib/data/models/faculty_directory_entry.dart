class FacultyDirectoryEntry {
  const FacultyDirectoryEntry({
    required this.uid,
    required this.fullName,
    required this.role,
    this.college,
    this.specialization,
    this.nominableAsAdviser = true,
    this.nominableAsPanelist = true,
  });

  final String uid;
  final String fullName;
  final String role;
  final String? college;
  final String? specialization;

  /// Whether a group may nominate this account as their adviser.
  ///
  /// Set by a coordinator on the Users screen. A missing key reads as
  /// `true`: every account predates this field, and "absent means not
  /// nominable" would make the whole faculty unpickable the moment this
  /// deployed.
  final bool nominableAsAdviser;

  /// Whether a group may nominate this account onto their panel.
  ///
  /// An ex-officio seat ignores this entirely — that seat comes from the
  /// office, not from a coordinator's list (spec D32).
  final bool nominableAsPanelist;

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
      nominableAsAdviser: map['nominableAsAdviser'] as bool? ?? true,
      nominableAsPanelist: map['nominableAsPanelist'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'role': role,
        'college': college,
        'specialization': specialization,
      };
}
