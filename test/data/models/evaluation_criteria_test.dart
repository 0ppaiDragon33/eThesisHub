import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

void main() {
  test('the eleven criteria sum to 100', () {
    final total =
        evaluationCriteria.fold<int>(0, (sum, c) => sum + c.weight);
    expect(total, 100);
  });

  test('each section sums to 50', () {
    int sum(EvaluationSection s) => evaluationCriteria
        .where((c) => c.section == s)
        .fold<int>(0, (t, c) => t + c.weight);

    expect(sum(EvaluationSection.content), 50);
    expect(sum(EvaluationSection.presentation), 50);
  });

  // D35. The printed form says Title (50%), which would make Section A
  // sum to 95 against its own stated 50%. This test is what stops someone
  // "correcting" the table back to the manual.
  test('Title is 5, not the 50 the printed form says', () {
    expect(criterionFor('title')!.weight, 5);
  });

  test('there are eight Content criteria and three Presentation', () {
    expect(
        evaluationCriteria
            .where((c) => c.section == EvaluationSection.content)
            .length,
        8);
    expect(
        evaluationCriteria
            .where((c) => c.section == EvaluationSection.presentation)
            .length,
        3);
  });

  // D38: the printed form gives comment lines to Section A only.
  test('only Content criteria take a comment', () {
    for (final c in evaluationCriteria) {
      expect(c.takesComment, c.section == EvaluationSection.content,
          reason: c.key);
    }
  });

  test('keys are unique', () {
    expect(criterionKeys.toSet().length, criterionKeys.length);
  });

  test('contentKeys is the eight Content keys in form order', () {
    expect(contentKeys, [
      'title', 'introduction', 'materialsAndMethods', 'result',
      'discussion', 'conclusion', 'recommendation', 'references',
    ]);
  });

  test('an unknown key resolves to null rather than throwing', () {
    expect(criterionFor('nope'), isNull);
  });
}
