import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';

/// Everything Form 3 prints — the adviser's letter asking the Dean to
/// convene the panel for a pre-oral defence.
///
/// Takes no repositories: [title] and [panelNames] are resolved by the
/// screen and passed in, exactly as `Form8Data` and `Form5cData` do.
///
/// The printed form's "Recommending Approval" (coordinator) and "Approved"
/// (dean) lines carry no data even in a filled letter — this app tracks
/// no separate digital sign-off for a defence REQUEST the way it tracks
/// coordinator-recommended/dean-approved on a thesis's nomination. Those
/// two lines print as ruled blanks for a wet signature on every letter
/// this generates, filled or not.
class Form3Data {
  const Form3Data({
    required this.presenterNames,
    required this.title,
    required this.panelNames,
    required this.college,
    this.scheduledAt,
    this.venue = '',
  });

  final List<String> presenterNames;
  final String title;
  final List<String> panelNames;
  final String college;
  final DateTime? scheduledAt;
  final String venue;

  factory Form3Data.assemble({
    required Thesis thesis,
    required Defence defence,
    required String title,
    required List<String> panelNames,
  }) {
    return Form3Data(
      presenterNames: thesis.memberNames,
      title: title,
      panelNames: panelNames,
      college: thesis.college,
      scheduledAt: defence.scheduledAt,
      venue: defence.venue,
    );
  }
}
