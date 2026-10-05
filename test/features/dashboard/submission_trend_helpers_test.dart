import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/submission_trend.dart';

Thesis made(DateTime createdAt) => Thesis(
      id: 't',
      leaderUid: 'l',
      memberNames: const [],
      workingTitle: 'T',
      college: 'CICT',
      program: 'BSIT',
      semester: 'First',
      academicYear: '2026-2027',
      status: ThesisStatus.draft,
      panelistUids: const [],
      createdAt: createdAt,
    );

void main() {
  test('the trend tooltip names the count and the month', () {
    expect(trendTooltip(8, 'Sep'), '8 groups · Sep');
    expect(trendTooltip(1, 'Oct'), '1 group · Oct');
    expect(trendTooltip(0, 'Apr'), '0 groups · Apr');
  });

  test('the submissions peek counts only this month', () {
    final now = DateTime(2026, 10, 15);
    final theses = [
      made(DateTime(2026, 10, 1)),
      made(DateTime(2026, 10, 14)),
      made(DateTime(2026, 9, 30)),
      made(DateTime(2025, 10, 5)),
    ];
    expect(submissionsThisMonth(theses, now: now), 2);
    expect(submissionsThisMonth(const [], now: now), 0);
  });

  test('the defences peek reads naturally', () {
    expect(defencesPeek(0), 'No defences');
    expect(defencesPeek(1), '1 defence');
    expect(defencesPeek(3), '3 defences');
  });
}
