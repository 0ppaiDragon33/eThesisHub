import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';

/// Form 5b's whole payload — the Presenter and Evaluator Profile that
/// sits ahead of Form 5c in the Guidelines and, per M6's D60, already had
/// every one of its fields borrowed into Form 5c's own header. Splitting
/// it out as its own document is therefore cheap: this class carries no
/// field Form5cData did not already resolve.
class Form5bData {
  const Form5bData({
    required this.presenterNames,
    required this.title,
    required this.defenceType,
    required this.presentedOn,
    required this.venue,
    required this.evaluatorName,
    required this.evaluatorField,
  });

  final List<String> presenterNames;
  final String title;
  final DefenceType defenceType;
  final DateTime? presentedOn;
  final String venue;
  final String evaluatorName;
  final String evaluatorField;

  /// The identical subset already assembled for a Form 5c sheet. A
  /// panelist who has generated Form 5c for a defence already has every
  /// field this needs — nothing here re-resolves anything Form5cData did
  /// not already resolve.
  factory Form5bData.fromForm5c(Form5cData d) {
    return Form5bData(
      presenterNames: d.presenterNames,
      title: d.title,
      defenceType: d.defenceType,
      presentedOn: d.presentedOn,
      venue: d.venue,
      evaluatorName: d.evaluatorName,
      evaluatorField: d.evaluatorField,
    );
  }
}
