import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';

Thesis buildThesis({List<String> members = const ['Santos, J.', 'Lim, K.']}) {
  return Thesis.fromMap('t1', {
    'leaderUid': 'l1',
    'memberNames': members,
    'workingTitle': 'Working title',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'status': 'titleApproved',
    'panelistUids': <String>['p1'],
    'createdAt': DateTime(2026, 8, 1),
  });
}

Defence buildDefence({DefenceType type = DefenceType.final_}) {
  return Defence.fromMap('d1', {
    'thesisId': 't1',
    'type': type.value,
    'scheduledAt': DateTime(2026, 9, 23, 9, 30),
    'venue': 'CICT AVR',
    'panelUids': <String>['p1'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': 'completed',
    'createdBy': 'c1',
  });
}

Evaluation buildEvaluation({
  Map<String, int>? scores,
  Map<String, String> comments = const {},
  String rating = 'pass',
}) {
  final s = scores ?? {for (final c in evaluationCriteria) c.key: c.weight};
  return Evaluation.fromMap('p1', {
    'evaluatorName': 'Dr. Reyes',
    'scores': s,
    'comments': comments,
    'total': totalOf(s),
    'rating': rating,
  });
}

Form5cData assemble({
  Thesis? thesis,
  Defence? defence,
  Evaluation? evaluation,
  String title = 'A Study of Coastal Fisheries',
  String evaluatorField = 'Information Technology',
}) {
  return Form5cData.assemble(
    thesis: thesis ?? buildThesis(),
    defence: defence ?? buildDefence(),
    evaluation: evaluation ?? buildEvaluation(),
    title: title,
    evaluatorField: evaluatorField,
  );
}

void main() {
  test('carries the identifying header the printed form lacks', () {
    final d = assemble();

    expect(d.presenterNames, ['Santos, J.', 'Lim, K.']);
    expect(d.title, 'A Study of Coastal Fisheries');
    expect(d.venue, 'CICT AVR');
    expect(d.presentedOn, DateTime(2026, 9, 23, 9, 30));
    expect(d.evaluatorName, 'Dr. Reyes');
    expect(d.evaluatorField, 'Information Technology');
  });

  // D59 + M4's D36: one panelist can hold TWO 5c sheets for one thesis,
  // one per defence. They must be distinguishable on the page.
  test('the defence type distinguishes the two sheets a panelist may hold',
      () {
    expect(assemble(defence: buildDefence(type: DefenceType.preOral))
        .defenceType, DefenceType.preOral);
    expect(assemble(defence: buildDefence(type: DefenceType.final_))
        .defenceType, DefenceType.final_);
  });

  test('a perfect sheet totals 50, 50 and 100', () {
    final d = assemble();
    expect(d.sectionATotal, 50);
    expect(d.sectionBTotal, 50);
    expect(d.finalGrade, 100);
  });

  test('the subtotals split the criteria by section', () {
    // Only Title (5, Content) and Alertness (25, Presentation) scored.
    final d = assemble(
      evaluation: buildEvaluation(scores: {
        for (final c in evaluationCriteria)
          c.key: switch (c.key) { 'title' => 5, 'alertness' => 25, _ => 0 },
      }),
    );

    expect(d.sectionATotal, 5);
    expect(d.sectionBTotal, 25);
    expect(d.finalGrade, 30);
  });

  test('comments come through, and an unscored criterion is zero not null',
      () {
    final d = assemble(
      evaluation: buildEvaluation(comments: {'title': 'Narrow it.'}),
    );

    expect(d.comments['title'], 'Narrow it.');
    expect(d.comments['result'], isNull);
    expect(d.scores['result'], isNotNull);
  });

  test('the rating comes through', () {
    expect(assemble().rating, PassFail.pass);
    expect(assemble(evaluation: buildEvaluation(rating: 'fail')).rating,
        PassFail.fail);
  });

  // The screen resolves these and passes them in; the data class must not
  // invent a placeholder when they are genuinely unknown.
  test('an unresolved specialization stays empty rather than guessing', () {
    expect(assemble(evaluatorField: '').evaluatorField, '');
  });

  test('a one-member group assembles without special-casing', () {
    expect(assemble(thesis: buildThesis(members: const ['Santos, J.']))
        .presenterNames, ['Santos, J.']);
  });
}
