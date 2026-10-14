import 'package:ethesishub/core/config/advising.dart';

class FacultyDirectoryEntry {
  const FacultyDirectoryEntry({
    required this.uid,
    required this.fullName,
    required this.role,
    this.college,
    this.specialization,
    this.nominableAsAdviser = true,
    this.nominableAsPanelist = true,
    this.adviseeCount = 0,
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

  /// How many groups this person holds as adviser (see `myAdviseeCountProvider`),
  /// kept here by their own app since students cannot count it themselves.
  /// 0 until their app has reported it.
  final int adviseeCount;

  /// At the limit: shown greyed out in the adviser pickers.
  bool get adviserFull => adviseeCount >= kMaxAdvisees;

  /// Shown beside the name in the pickers: specialization, then college
  /// ("MIT · CICI").
  String get subtitle => [specialization, college]
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
      adviseeCount: (map['adviseeCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'role': role,
        'college': college,
        'specialization': specialization,
      };
}
