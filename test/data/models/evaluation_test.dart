import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

Map<String, int> fullScores({int each = 1}) =>
    {for (final c in evaluationCriteria) c.key: each};

void main() {
  test('totalOf sums the eleven scores', () {
    expect(totalOf(fullScores()), 11);
  });

  test('a perfect sheet totals 100', () {
    final perfect = {for (final c in evaluationCriteria) c.key: c.weight};
    expect(totalOf(perfect), 100);
  });

  test('sectionTotal splits 50 and 50 on a perfect sheet', () {
    final e = Evaluation(
      evaluatorUid: 'p1',
      scores: {for (final c in evaluationCriteria) c.key: c.weight},
      comments: const {},
      total: 100,
      rating: PassFail.pass,
    );
    expect(e.sectionTotal(EvaluationSection.content), 50);
    expect(e.sectionTotal(EvaluationSection.presentation), 50);
  });

  test('fromMap reads scores, comments, total and rating', () {
    final e = Evaluation.fromMap('p1', {
      'scores': {'title': 4, 'alertness': 21},
      'comments': {'title': 'Narrow it.'},
      'total': 25,
      'rating': 'pass',
      'submittedAt': DateTime(2026, 9, 23, 11),
      'updatedAt': DateTime(2026, 9, 23, 12),
    });

    expect(e.evaluatorUid, 'p1');
    expect(e.scores['title'], 4);
    expect(e.comments['title'], 'Narrow it.');
    expect(e.total, 25);
    expect(e.rating, PassFail.pass);
    expect(e.submittedAt, DateTime(2026, 9, 23, 11));
    expect(e.updatedAt, DateTime(2026, 9, 23, 12));
  });

  // The same reasoning as DefenceType.fromString: a typo must not silently
  // become a pass. Here it must not silently become a fail either, so the
  // model surfaces null and the screen decides.
  test('an unreadable rating is null, not a default', () {
    expect(PassFail.fromString('Pass'), isNull);
    expect(PassFail.fromString(null), isNull);
    expect(PassFail.fromString('pass'), PassFail.pass);
    expect(PassFail.fromString('fail'), PassFail.fail);
  });

  test('a score key this build does not know is ignored, not fatal', () {
    final e = Evaluation.fromMap('p1', {
      'scores': {'title': 4, 'someFutureCriterion': 9},
      'comments': const <String, dynamic>{},
      'total': 13,
      'rating': 'fail',
    });
    // Kept in `scores` verbatim -- it is someone's permanent record --
    // but excluded from a section subtotal, which can only count criteria
    // it can place in a section.
    expect(e.scores['someFutureCriterion'], 9);
    expect(e.sectionTotal(EvaluationSection.content), 4);
  });

  test('a missing scores map reads as empty rather than throwing', () {
    final e = Evaluation.fromMap('p1', const {});
    expect(e.scores, isEmpty);
    expect(e.total, 0);
    expect(e.rating, isNull);
  });
}
