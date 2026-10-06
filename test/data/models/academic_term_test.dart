import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/academic_term.dart';

const t = AcademicTerm.new;

void main() {
  test('reads the start year and orders semesters', () {
    final a = t(semester: 'Second', academicYear: '2026-2027');
    final b = t(semester: 'First', academicYear: '2027-2028');
    expect(a.startYear, 2026);
    expect(a.isValid, isTrue);
    expect(b.index! - a.index!, 1, reason: 'the very next semester');
  });

  test('next: First to Second, Second to the next year\'s First', () {
    expect(t(semester: 'First', academicYear: '2026-2027').next,
        t(semester: 'Second', academicYear: '2026-2027'));
    expect(t(semester: 'Second', academicYear: '2026-2027').next,
        t(semester: 'First', academicYear: '2027-2028'));
  });

  test('short reads like "2nd sem 2026–27"', () {
    expect(t(semester: 'Second', academicYear: '2026-2027').short,
        '2nd sem 2026–27');
    expect(t(semester: 'First', academicYear: '2099-2100').short,
        '1st sem 2099–00');
  });

  test('a malformed term is invalid', () {
    expect(t(semester: 'Summer', academicYear: '2026-2027').isValid, isFalse);
    expect(t(semester: 'First', academicYear: '26-27').isValid, isFalse);
    expect(t(semester: '', academicYear: '').index, isNull);
  });

  test('year level: 3rd year at the start, one more per academic year', () {
    final started = t(semester: 'Second', academicYear: '2026-2027');
    expect(yearLevelIn(started, started), 3);
    // The 1st sem of the next academic year is 4th year.
    expect(yearLevelIn(started, t(semester: 'First', academicYear: '2027-2028')),
        4);
    expect(yearLevelIn(started, t(semester: 'Second', academicYear: '2027-2028')),
        4);
    // Before the start makes no sense.
    expect(yearLevelIn(started, t(semester: 'First', academicYear: '2025-2026')),
        isNull);
  });

  test('year level labels', () {
    expect(yearLevelLabel(1), '1st year');
    expect(yearLevelLabel(2), '2nd year');
    expect(yearLevelLabel(3), '3rd year');
    expect(yearLevelLabel(4), '4th year');
    expect(yearLevelLabel(11), '11th year');
  });
}
