import 'package:ethesishub/data/models/evaluation_criteria.dart';

/// Guidelines §8a: *"The Thesis Panel Members shall rate the student using
/// the Pass or Fail grading scheme."*
///
/// Used for two different things that must never be confused: one
/// panelist's own rating on their sheet, and the panel's deliberated
/// verdict under §8b, which the adviser records and which is NEVER
/// computed from the ratings (D41).
enum PassFail {
  pass,
  fail;

  String get value => name;

  String get label => this == PassFail.pass ? 'Pass' : 'Fail';

  /// Null rather than a default. There is no safe default here: defaulting
  /// to `pass` passes a student on corrupt data, and defaulting to `fail`
  /// fails one. The caller must handle "we cannot read this".
  static PassFail? fromString(String? raw) {
    for (final v in PassFail.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// The sum of a score map. The stored `total` is written from this, and
/// `firestore.rules` recomputes the same sum before accepting a write --
/// a stored total that could disagree with its own scores would be worse
/// than no stored total at all.
int totalOf(Map<String, int> scores) =>
    scores.values.fold<int>(0, (sum, v) => sum + v);

/// One panelist's completed Form 5c for one defence.
///
/// Keyed in Firestore by the evaluator's uid, so a panelist has exactly
/// one and cannot file a second under another name.
class Evaluation {
  const Evaluation({
    required this.evaluatorUid,
    required this.evaluatorName,
    required this.scores,
    required this.comments,
    required this.total,
    required this.rating,
    this.submittedAt,
    this.updatedAt,
  });

  final String evaluatorUid;

  /// The evaluator's name AS IT STOOD WHEN THEY SUBMITTED, denormalized
  /// here rather than resolved from `users/{uid}` on read -- the same
  /// treatment, and the same reason, as `authorName` on a defence
  /// comment. This is a permanent academic record: who marked this sheet
  /// must not silently change when the account behind the uid is renamed,
  /// reassigned or deactivated years later. A raw uid in its place is not
  /// an identity to anyone reading the grade sheet.
  ///
  /// Empty for a document written before this field existed; a screen
  /// falls back to the uid rather than rendering a blank column.
  final String evaluatorName;

  /// Criterion key -> points, each 0..that criterion's weight (D34).
  final Map<String, int> scores;

  /// Criterion key -> remark, for the eight Content criteria only.
  /// Optional per criterion (D45): requiring all eight produces filler.
  final Map<String, String> comments;

  /// 0..100. Stored rather than derived so a list can compare and order
  /// without loading eleven fields.
  final int total;

  /// This panelist's own §8a rating. Null only when the stored value is
  /// unreadable -- see [PassFail.fromString].
  final PassFail? rating;

  /// When this panelist first submitted. Survives every later edit, so
  /// "when did they submit" stays answerable (the rules pin it too).
  final DateTime? submittedAt;

  final DateTime? updatedAt;

  /// The subtotal for one half of the form.
  ///
  /// Counts only keys this build can place in a section. A key written by
  /// a future build is kept in [scores] -- it is part of someone's
  /// permanent record -- but cannot be added to a section it has no
  /// section for.
  int sectionTotal(EvaluationSection section) {
    var sum = 0;
    scores.forEach((key, value) {
      if (criterionFor(key)?.section == section) sum += value;
    });
    return sum;
  }

  factory Evaluation.fromMap(String evaluatorUid, Map<String, dynamic> map) {
    final rawScores = map['scores'] as Map? ?? const {};
    final rawComments = map['comments'] as Map? ?? const {};

    return Evaluation(
      evaluatorUid: evaluatorUid,
      evaluatorName: map['evaluatorName'] as String? ?? '',
      scores: {
        for (final e in rawScores.entries)
          if (e.value is int) e.key as String: e.value as int,
      },
      comments: {
        for (final e in rawComments.entries)
          if (e.value is String) e.key as String: e.value as String,
      },
      total: map['total'] as int? ?? 0,
      rating: PassFail.fromString(map['rating'] as String?),
      submittedAt: map['submittedAt'] as DateTime?,
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}
