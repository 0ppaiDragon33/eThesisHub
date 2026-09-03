import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';

/// Everything Form 5a prints — the student's letter requesting the final
/// oral defence. See `Form3Data`'s doc comment for why the coordinator
/// and dean lines carry no data even when the letter is otherwise filled:
/// this app tracks no digital sign-off for a defence request.
class Form5aData {
  const Form5aData({
    required this.presenterNames,
    required this.title,
    required this.college,
    this.scheduledAt,
    this.venue = '',
  });

  final List<String> presenterNames;
  final String title;
  final String college;
  final DateTime? scheduledAt;
  final String venue;

  factory Form5aData.assemble({
    required Thesis thesis,
    required Defence defence,
    required String title,
  }) {
    return Form5aData(
      presenterNames: thesis.memberNames,
      title: title,
      college: thesis.college,
      scheduledAt: defence.scheduledAt,
      venue: defence.venue,
    );
  }
}
