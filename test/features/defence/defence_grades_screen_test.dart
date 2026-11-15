import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/features/defence/defence_grades_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Same shape as the `seed`, extended with the `evaluations`
/// subcollection and the release/verdict fields this screen reads. Copied
/// rather than shared: the two suites must not share a file.
Future<FakeFirebaseFirestore> _seedDefence({
  String status = 'completed',
  DateTime? evaluationsReleasedAt,
  String? verdict,
  String? verdictRecordedBy,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR',
    'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    if (evaluationsReleasedAt != null)
      'evaluationsReleasedAt': Timestamp.fromDate(evaluationsReleasedAt),
    'panelVerdict': ?verdict,
    if (verdict != null) 'verdictRecordedBy': verdictRecordedBy ?? 'a1',
    if (verdict != null)
      'verdictRecordedAt': Timestamp.fromDate(DateTime(2026, 9, 23, 10)),
  });
  return db;
}

/// REAL scores, not an empty map: seeded empty, every cell in the table
/// rendered through the `?? 0` fallback and the table test proved only
/// that eleven columns existed, never that a stored score reached the
/// column it belongs to. Scaled off [total] so the row still sums to what
/// the panel mean is computed from.
Map<String, int> _scoresFor(int total) {
  final scores = <String, int>{};
  var remaining = total;
  for (final c in evaluationCriteria) {
    final v = ((c.weight * total) / 100).floor().clamp(0, c.weight);
    scores[c.key] = v;
    remaining -= v;
  }
  // Whatever rounding dropped goes onto the first criterion with room, so
  // totalOf(scores) == total exactly.
  for (final c in evaluationCriteria) {
    if (remaining <= 0) break;
    final room = c.weight - scores[c.key]!;
    final add = room < remaining ? room : remaining;
    scores[c.key] = scores[c.key]! + add;
    remaining -= add;
  }
  return scores;
}

Future<void> _writeEvaluation(
  FakeFirebaseFirestore db,
  String uid,
  int total, {
  String? name,
  Map<String, String> comments = const {},
  // The app records each submitter on the defence in the same batch as the
  // sheet; `false` seeds a sheet saved before that record existed.
  bool record = true,
}) async {
  // The written half lives on its own document, as the app writes it, so
  // the group can read it without a score.
  await db
      .collection('defenses')
      .doc('d1')
      .collection('remarks')
      .doc(uid)
      .set({'evaluatorName': name ?? '', 'comments': comments});
  if (record) {
    await db.collection('defenses').doc('d1').update({
      'submittedUids': FieldValue.arrayUnion([uid]),
    });
  }
  await db
      .collection('defenses')
      .doc('d1')
      .collection('evaluations')
      .doc(uid)
      .set({
        'evaluatorName': ?name,
        'scores': _scoresFor(total),
        'comments': comments,
        'total': total,
        'rating': 'pass',
        'submittedAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9, 30)),
      });
}

/// Panel of p1, p2; only p1 has submitted, and the grades are not yet
/// released.
Future<FakeFirebaseFirestore> seedWithOne() async {
  final db = await _seedDefence();
  await _writeEvaluation(db, 'p1', 100, name: 'Dr. Panelist One');
  return db;
}

/// Both panelists have submitted and the adviser has released the grades.
Future<FakeFirebaseFirestore> seedReleased({
  int second = 100,
  String? verdict,
}) async {
  final db = await _seedDefence(
    evaluationsReleasedAt: DateTime(2026, 9, 23, 11),
    verdict: verdict,
  );
  await _writeEvaluation(
    db,
    'p1',
    100,
    name: 'Dr. Panelist One',
    comments: const {'title': 'Narrow it.'},
  );
  await _writeEvaluation(db, 'p2', second, name: 'Dr. Panelist Two');
  return db;
}

/// Nobody has submitted, and the grades are not yet released.
Future<FakeFirebaseFirestore> seedNone() => _seedDefence();

Widget app(FakeFirebaseFirestore db, String uid) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: DefenceGradesScreen(defenceId: 'd1')),
    ),
  );
}

/// The grades table has a column per criterion (11) plus panelist, total
/// and rating, which is wider and taller than the default 800x600 test
/// surface: the repo's own idiom, see `useTallSurface` in
/// `evaluation_screen_test.dart`.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  // The release is for the students: the group's leader reads the same
  // table, read-only, and records nothing.
  testWidgets('after release the group\'s leader reads the remarks, no scores',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('leaderGradesIntro')), findsOneWidget);
    // One card per panelist; the silent one says so and cannot be opened.
    expect(find.byKey(const Key('remarksCard-p1')), findsOneWidget);
    expect(find.byKey(const Key('remarksCard-p2')), findsOneWidget);
    expect(find.text('Dr. Panelist One'), findsOneWidget);
    expect(find.text('No written remarks'), findsOneWidget);
    // Not one number: no table, no mean, no pass mark.
    expect(find.byKey(const Key('gradesTable')), findsNothing);
    expect(find.byKey(const Key('panelMean')), findsNothing);
    expect(find.byKey(const Key('recordVerdict')), findsNothing);
    expect(find.byKey(const Key('releaseEvaluations')), findsNothing);
  });

  testWidgets('opening a panelist\'s card shows their remarks, no scores',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'l1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('remarksCard-p1')));
    await tester.pumpAndSettle();

    final detail = find.byKey(const Key('remarksDetail'));
    expect(detail, findsOneWidget);
    expect(find.descendant(of: detail, matching: find.text('Dr. Panelist One')),
        findsOneWidget);
    expect(find.descendant(of: detail, matching: find.text('Narrow it.')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('closeRemarks')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remarksDetail')), findsNothing);
  });

  testWidgets('a released defense with no remarks says so to the leader',
      (tester) async {
    final db = await _seedDefence(
        evaluationsReleasedAt: DateTime(2026, 9, 23, 11));
    await _writeEvaluation(db, 'p1', 100, name: 'Dr. Panelist One');
    await tester.pumpWidget(app(db, 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noRemarks')), findsOneWidget);
    expect(find.byKey(const Key('panelMean')), findsNothing);
  });

  testWidgets('before release the group\'s leader sees no grades',
      (tester) async {
    await tester.pumpWidget(app(await seedWithOne(), 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notReleasedNotice')), findsOneWidget);
    expect(find.byKey(const Key('panelMean')), findsNothing);
    expect(find.byKey(const Key('leaderGradesIntro')), findsNothing);
  });

  testWidgets('before release it shows the count and no scores', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submittedCount')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('submittedCount'))).data,
      '1 of 4 have submitted',
    );
    expect(find.byKey(const Key('gradesTable')), findsNothing);
  });

  // The mitigation. The count is on the button, so releasing early is a
  // visible choice rather than an accident.
  testWidgets('release stays locked until every grader has submitted',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting on 3 more evaluations'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('releaseEvaluations')))
            .onPressed,
        isNull);
  });

  testWidgets('once every sheet is in, release opens', (tester) async {
    useTallSurface(tester);
    final db = await seedWithOne();
    for (final uid in ['p2', 'c1', 'dn1']) {
      await _writeEvaluation(db, uid, 90, name: 'Grader $uid');
    }
    await tester.pumpWidget(app(db, 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('Release evaluations'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('releaseEvaluations')))
            .onPressed,
        isNotNull);
  });

  // Sheets saved before submissions were recorded are on file but not on
  // the list the rules judge, so release stays locked and the screen says
  // what unlocks it.
  testWidgets('sheets that were never recorded keep release locked and say '
      'why', (tester) async {
    useTallSurface(tester);
    final db = await _seedDefence();
    for (final uid in ['p1', 'p2', 'c1', 'dn1']) {
      await _writeEvaluation(db, uid, 90, name: 'Grader $uid', record: false);
    }
    await tester.pumpWidget(app(db, 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('4 of 4 have submitted'), findsOneWidget);
    expect(find.byKey(const Key('unrecordedNote')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('releaseEvaluations')))
            .onPressed,
        isNull);
  });

  // The count alone is not the gate: four sheets are in, which is the
  // required four, but panelist p2 has not graded. Release must stay locked.
  testWidgets('release stays locked while a panelist has not submitted, '
      'even when the sheet count is met', (tester) async {
    useTallSurface(tester);
    final db = await seedWithOne(); // p1 only
    for (final uid in ['c1', 'dn1', 'extra-office-holder']) {
      await _writeEvaluation(db, uid, 90, name: 'Grader $uid');
    }
    await tester.pumpWidget(app(db, 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('4 of 4 have submitted'), findsOneWidget);
    expect(find.text('Waiting on 1 more evaluation'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('releaseEvaluations')))
            .onPressed,
        isNull);
  });

  // Ruling 2: before release, a panelist never opens the evaluations list
  // (the rules still deny it to them), so they see only whether THEY have
  // submitted, never a count of others, and never the release control.
  testWidgets(
    'before release a panelist sees only their own submission status',
    (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(app(await seedWithOne(), 'p1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mySubmissionStatus')), findsOneWidget);
      expect(find.byKey(const Key('submittedCount')), findsNothing);
      expect(find.byKey(const Key('releaseEvaluations')), findsNothing);
    },
  );

  testWidgets('after release the table shows every panelist\'s total', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gradesTable')), findsOneWidget);
    expect(find.byKey(const Key('panelMean')), findsOneWidget);
  });

  // On a narrow screen the panelists' columns slide sideways while the
  // criterion column stays put; nothing may overflow the page.
  testWidgets('the grades slide on a 360dp phone and the labels stay',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final first = evaluationCriteria.first;
    final label = find.text('${first.label}  /${first.weight}');
    final heading = find.byKey(const ValueKey('heading_p2'));
    expect(label, findsOneWidget);
    final labelBefore = tester.getTopLeft(label);
    final headingBefore = tester.getTopLeft(heading);

    await tester.drag(find.byKey(const Key('gradesScroll')), const Offset(-300, 0));
    await tester.pumpAndSettle();

    // The grades moved; the criterion did not.
    expect(tester.getTopLeft(heading).dx, lessThan(headingBefore.dx));
    expect(tester.getTopLeft(label), labelBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a panelist name is drawn in full, not cut short', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    final heading = find.text('Dr. Panelist One');
    expect(heading, findsOneWidget);
    final text = tester.widget<Text>(heading);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(text.softWrap, isTrue);
    expect(tester.takeException(), isNull);
  });

  // Reported from a real screen: "Alertness and smartness in answering
  // question /25" (the form's own wording) was cut off mid-word by a
  // fixed 60dp row height. The row now grows to whatever the label needs.
  testWidgets('the longest criterion label is drawn in full, not clipped', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    final longest = find.textContaining('Alertness and smartness');
    expect(longest, findsOneWidget);
    // It runs to four lines at this column width. A row capped at 60 could
    // not have drawn them, which is exactly what went wrong.
    expect(tester.getSize(longest.first).height, greaterThan(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the table is a bordered surface, with its structural rows '
      'set apart', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    // Without the border the section headers and the final-grade row read
    // as more criteria, and the table stops looking like a form.
    final bordered = find
        .ancestor(
          of: find.byKey(const Key('gradesTable')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border != null,
          ),
        )
        .evaluate();
    expect(bordered, isNotEmpty);

    for (final key in [
      const ValueKey('section_content'),
      const ValueKey('section_presentation'),
      const ValueKey('row_total'),
    ]) {
      final box = tester.widget<Container>(find.byKey(key));
      expect(
        (box.decoration as BoxDecoration).color,
        isNotNull,
        reason: '$key should be tinted',
      );
    }
  });

  testWidgets('the table fits a wide screen without clipping either', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel mean is the mean of the submitted totals', (
    tester,
  ) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 50.
    await tester.pumpWidget(app(await seedReleased(second: 50), 'p1'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('panelMean'))).data,
      '75.0',
    );
  });

  // .round() rendered 83.5 and 84.4 identically, on the one number the
  // panel deliberates over.
  testWidgets('the panel mean keeps a decimal place', (tester) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 67: a mean of 83.5.
    await tester.pumpWidget(app(await seedReleased(second: 67), 'p1'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('panelMean'))).data,
      '83.5',
    );
  });

  // Seeded with an empty score map, every cell in this table rendered
  // through the ?? 0 fallback and this proved nothing about the wiring.
  testWidgets('a stored score reaches its own column', (tester) async {
    useTallSurface(tester);
    final db = await seedReleased();
    await tester.pumpWidget(app(db, 'p1'));
    await tester.pumpAndSettle();

    // Read straight off the seeded document: Evaluation.fromMap expects
    // the repository's already-converted DateTimes, and the point here is
    // what the SCREEN did with what was stored, not the model layer.
    final storedScores =
        ((await db
                        .collection('defenses')
                        .doc('d1')
                        .collection('evaluations')
                        .doc('p1')
                        .get())
                    .data()!['scores']
                as Map)
            .cast<String, int>();

    // Criteria are ROWS and panelists are COLUMNS: read down p1's column.
    for (final c in evaluationCriteria) {
      final cell = tester.widget<Text>(
        find.byKey(ValueKey('score_${c.key}_p1')),
      );
      expect(cell.data, '${storedScores[c.key]}', reason: c.key);
      // A perfect sheet, so every criterion carries its own DIFFERENT
      // weight: a cell wired to the wrong row would show as a mismatch
      // rather than coincide.
      expect(storedScores[c.key], c.weight, reason: c.key);
    }
  });

  testWidgets('every criterion gets a row, under its own section', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    for (final c in evaluationCriteria) {
      expect(find.byKey(ValueKey('criterion_${c.key}')), findsOneWidget,
          reason: c.key);
    }
    // Form 5c's own A/B structure.
    for (final s in EvaluationSection.values) {
      expect(find.byKey(ValueKey('section_${s.name}')), findsOneWidget,
          reason: s.name);
    }
    expect(find.byKey(const ValueKey('row_total')), findsOneWidget);
    expect(find.byKey(const ValueKey('row_rating')), findsOneWidget);
  });

  // §6 wants names on this screen, not raw Firebase uids.
  testWidgets('the table names the panelist, not their uid', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Panelist One'), findsWidgets);
    expect(find.text('p1'), findsNothing);
  });

  testWidgets('a per-criterion remark is attributed by name', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Panelist One: Narrow it.'), findsOneWidget);
  });

  // A sheet written before evaluatorName existed still has to identify
  // someone: the uid is a poor identity but it is not a blank cell.
  testWidgets('a sheet with no stored name falls back to the uid', (
    tester,
  ) async {
    useTallSurface(tester);
    final db = await _seedDefence(
      evaluationsReleasedAt: DateTime(2026, 9, 23, 11),
    );
    await _writeEvaluation(db, 'p1', 100);
    await tester.pumpWidget(app(db, 'p1'));
    await tester.pumpAndSettle();

    expect(find.text('p1'), findsOneWidget);
  });

  // Finding 5. The count alone does not tell the adviser WHO is missing,
  // which is what makes releasing at 2 of 3 a considered choice.
  testWidgets('before release the adviser sees who has submitted, by name', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('submittedNames'))).data,
      'Dr. Panelist One',
    );
  });

  testWidgets('with nobody submitted there is no roster, only the count', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submittedNames')), findsNothing);
  });

  testWidgets('the adviser records the verdict after release', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recordVerdict')), findsOneWidget);
  });

  testWidgets('a panelist may not record the verdict', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recordVerdict')), findsNothing);
  });

  // The adviser is visibly the scribe.
  testWidgets('a recorded verdict names who recorded it', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(verdict: 'pass'), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verdict')), findsOneWidget);
    // "the adviser", never a uid: the rules pin verdictRecordedBy to the
    // writer's own uid on the only arm that can set it, and only the
    // adviser passes that arm, so the role is the identity here.
    final scribe = tester
        .widget<Text>(find.byKey(const Key('verdictScribe')))
        .data!;
    expect(scribe, contains('Recorded by the adviser'));
    expect(scribe, isNot(contains('a1')));
    // The spec wants the timestamp beside the scribe; it was never shown.
    expect(scribe, contains('23/9/2026'));
    expect(find.byKey(const Key('recordVerdict')), findsNothing);
  });

  testWidgets('no evaluations yet says so, and does not look like a zero', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('submittedCount'))).data,
      '0 of 4 have submitted',
    );
    expect(find.byKey(const Key('panelMean')), findsNothing);
  });

  // pump() once, not pumpAndSettle: settling resolves the stream and the
  // assertion becomes vacuous.
  testWidgets('shows a loading state before the defense resolves', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pump();

    expect(find.byKey(const Key('gradesLoading')), findsOneWidget);
  });

  // ISUFST's passing mark is 75. The spec supersedes the blanket "never
  // computed" for this one guard: the panel still decides, but the system
  // refuses to record a Pass the numbers cannot carry. Only the adviser
  // (a1) sees these controls at all.
  SegmentedButton<PassFail> verdictControl(WidgetTester tester) =>
      tester.widget<SegmentedButton<PassFail>>(
        find.byType(SegmentedButton<PassFail>),
      );

  bool segmentEnabled(SegmentedButton<PassFail> seg, PassFail value) =>
      seg.segments.firstWhere((s) => s.value == value).enabled;

  testWidgets('a sub-75 panel mean locks Pass and leaves Fail selectable', (
    tester,
  ) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 48: a mean of 74.0, below the passing mark.
    await tester.pumpWidget(app(await seedReleased(second: 48), 'a1'));
    await tester.pumpAndSettle();

    final seg = verdictControl(tester);
    expect(segmentEnabled(seg, PassFail.pass), isFalse);
    expect(segmentEnabled(seg, PassFail.fail), isTrue);
    // The lock explains itself, so a mean that DISPLAYS as 75.0 while
    // actually sitting at 74.96 never looks like a broken button.
    expect(find.byKey(const Key('verdictLocked')), findsOneWidget);
  });

  // The boundary: 75 is a pass, not a fail, so Fail is the locked one.
  testWidgets('a mean of exactly 75 admits Pass and locks Fail', (tester) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 50: a mean of exactly 75.0.
    await tester.pumpWidget(app(await seedReleased(second: 50), 'a1'));
    await tester.pumpAndSettle();

    final seg = verdictControl(tester);
    expect(segmentEnabled(seg, PassFail.pass), isTrue);
    expect(segmentEnabled(seg, PassFail.fail), isFalse);
    expect(find.byKey(const Key('verdictLocked')), findsNothing);
    expect(find.byKey(const Key('verdictFailLocked')), findsOneWidget);
  });

  testWidgets('a comfortably passing mean admits only Pass', (tester) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 100: a mean of 100.
    await tester.pumpWidget(app(await seedReleased(), 'a1'));
    await tester.pumpAndSettle();

    final seg = verdictControl(tester);
    expect(segmentEnabled(seg, PassFail.pass), isTrue);
    expect(segmentEnabled(seg, PassFail.fail), isFalse);
  });

  // The two locks are exclusive: exactly one verdict is ever open.
  testWidgets('a sub-75 mean leaves Fail open and shows no Fail lock', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(second: 48), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verdictFailLocked')), findsNothing);
  });

  // Defence in depth, the other way: at or above the mark the record
  // button must not act on a Fail the gate forbids.
  testWidgets('at 75 or more, tapping Fail never arms the record button', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<PassFail>),
        matching: find.text('Fail'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('recordVerdict')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('recording a verdict confirms before it is written', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<PassFail>),
        matching: find.text('Pass'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recordVerdict')));
    await tester.pumpAndSettle();

    // A verdict is final, so pressing Record asks first.
    expect(find.byKey(const Key('confirmVerdict')), findsOneWidget);
    expect(find.text('Record a Pass verdict?'), findsOneWidget);
  });

  // Defence in depth: the record button must not act on a Pass the gate
  // forbids, even if selection state drifted there somehow.
  testWidgets('under 75, tapping Pass never arms the record button', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(second: 48), 'a1'));
    await tester.pumpAndSettle();

    // Scoped to the verdict control: "Pass" also renders once per panelist
    // in the rating column, so a bare find.text is ambiguous.
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<PassFail>),
        matching: find.text('Pass'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('recordVerdict')),
    );
    expect(button.onPressed, isNull);
  });
}
