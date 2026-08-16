import 'package:ethesishub/data/models/user_role.dart';

/// A pending or completed promotion, keyed in Firestore by the invitee's
/// lowercased email — the address is the document id, not a field.
///
/// Invites carry `college` and `specialization` so a promoted account is
/// correct from its very first sign-in. Nothing else fills those two fields:
/// registration collects a program but never a college,
/// `createStudentProfile` hardcodes `specialization: null`, and before this
/// they could only be typed into the Firebase Console by hand. The
/// coordinator issuing the invite already knows both.
///
/// An invite is marked consumed rather than deleted once applied, so a
/// completed promotion always leaves a record — the invitee can never erase
/// the evidence of their own elevation.
class FacultyInvite {
  const FacultyInvite({
    required this.email,
    required this.role,
    required this.invitedBy,
    this.createdAt,
    this.consumedAt,
    this.college,
    this.specialization,
  });

  /// The lowercased email, which is also the Firestore document id.
  final String email;
  final UserRole role;
  final String invitedBy;
  final DateTime? createdAt;

  /// Null while the invite is still open. Set by the invitee themselves when
  /// they apply it.
  final DateTime? consumedAt;

  final String? college;
  final String? specialization;

  bool get isConsumed => consumedAt != null;

  factory FacultyInvite.fromMap(String email, Map<String, dynamic> map) {
    return FacultyInvite(
      email: email,
      role: UserRole.tryParse(map['role'] as String?) ?? UserRole.faculty,
      invitedBy: map['invitedBy'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
      consumedAt: map['consumedAt'] as DateTime?,
      college: map['college'] as String?,
      specialization: map['specialization'] as String?,
    );
  }
}
