/// One title a group is putting forward at their title defence, with the
/// justification document that argues for it.
class CandidateTitle {
  const CandidateTitle({
    required this.id,
    required this.titleText,
    required this.justificationPath,
    required this.justificationUrl,
    required this.round,
    this.submittedAt,
  });

  final String id;
  final String titleText;

  /// Supabase object path — what we would need to delete the file.
  final String justificationPath;

  /// Public URL — what the panel opens. The bucket is public and the path is
  /// an unguessable UUID.
  final String justificationUrl;

  /// Which submission this belonged to. A rejected set is kept, not deleted,
  /// so the round is what separates it from the resubmission.
  final int round;

  final DateTime? submittedAt;

  factory CandidateTitle.fromMap(String id, Map<String, dynamic> map) {
    return CandidateTitle(
      id: id,
      titleText: map['titleText'] as String? ?? '',
      justificationPath: map['justificationPath'] as String? ?? '',
      justificationUrl: map['justificationUrl'] as String? ?? '',
      round: (map['round'] as num?)?.toInt() ?? 0,
      submittedAt: map['submittedAt'] as DateTime?,
    );
  }
}
