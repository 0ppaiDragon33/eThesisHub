/// One title a group is putting forward at their title defence, with the
/// justification document that argues for it.
class CandidateTitle {
  const CandidateTitle({
    required this.id,
    required this.titleText,
    required this.justificationPath,
    required this.justificationUrl,
    required this.round,
    required this.position,
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

  /// Where this title sat in the list the group submitted, counting from 0.
  ///
  /// Recorded explicitly because neither alternative orders them: document
  /// ids are auto-generated and random, and every candidate in a submission
  /// is written in ONE batch, so `submittedAt` is the identical server
  /// timestamp on all of them and ties fall back to that random id. The
  /// panel was being shown the group's titles shuffled.
  final int position;

  final DateTime? submittedAt;

  factory CandidateTitle.fromMap(String id, Map<String, dynamic> map) {
    return CandidateTitle(
      id: id,
      titleText: map['titleText'] as String? ?? '',
      justificationPath: map['justificationPath'] as String? ?? '',
      justificationUrl: map['justificationUrl'] as String? ?? '',
      round: (map['round'] as num?)?.toInt() ?? 0,
      // Absent on anything written before positions were recorded; those all
      // collapse to 0 and keep their previous order among themselves rather
      // than vanishing from the list.
      position: (map['position'] as num?)?.toInt() ?? 0,
      submittedAt: map['submittedAt'] as DateTime?,
    );
  }
}
