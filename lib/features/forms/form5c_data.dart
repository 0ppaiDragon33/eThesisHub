import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/models/thesis.dart';

/// Everything one panelist's Form 5c prints, gathered and nothing more.
///
/// Takes no repositories: [title] and [evaluatorField] are resolved by the
/// screen and passed in, exactly as `Form1Data` takes `directoryNames`.
/// That is what keeps `assemble` testable without standing up Firestore.
class Form5cData {
  const Form5cData({
    required this.presenterNames,
    required this.title,
    required this.defenceType,
    required this.presentedOn,
    required this.venue,
    required this.evaluatorName,
    required this.evaluatorField,
    required this.scores,
    required this.comments,
    required this.sectionATotal,
    required this.sectionBTotal,
    required this.finalGrade,
    required this.rating,
  });

  final List<String> presenterNames;
  final String title;

  /// M4 applies Form 5c to BOTH defences (its D36), so one panelist can
  /// hold two completed sheets for the same thesis. Printed on the page so
  /// the two are distinguishable by more than a date.
  final DefenceType defenceType;

  final DateTime? presentedOn;
  final String venue;
  final String evaluatorName;

  /// Empty when the directory has no entry for this evaluator. The form
  /// prints a ruled line either way, so an empty string is honest — the
  /// data class does not invent a placeholder.
  final String evaluatorField;

  final Map<String, int> scores;
  final Map<String, String> comments;
  final int sectionATotal;
  final int sectionBTotal;
  final int finalGrade;
  final PassFail? rating;

  factory Form5cData.assemble({
    required Thesis thesis,
    required Defence defence,
    required Evaluation evaluation,
    required String title,
    required String evaluatorField,
  }) {
    return Form5cData(
      presenterNames: thesis.memberNames,
      title: title,
      defenceType: defence.type,
      presentedOn: defence.scheduledAt,
      venue: defence.venue,
      evaluatorName: evaluation.evaluatorName,
      evaluatorField: evaluatorField,
      scores: evaluation.scores,
      comments: evaluation.comments,
      sectionATotal: evaluation.sectionTotal(EvaluationSection.content),
      sectionBTotal: evaluation.sectionTotal(EvaluationSection.presentation),
      // The stored total, not a re-sum: the rules verified it against the
      // scores when it was written, so recomputing here could only ever
      // disagree with the record.
      finalGrade: evaluation.total,
      rating: evaluation.rating,
    );
  }
}
