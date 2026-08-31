import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/features/defence/defence_grades_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Same shape as Task 9's `seed`, extended with the `evaluations`
/// subcollection and the release/verdict fields this screen reads. Copied
/// rather than shared -- the two suites must not share a file.
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
}) async {
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
Future<FakeFirebaseFirestore> seedReleased({int second = 100, String? verdict}) async {
  final db = await _seedDefence(
    evaluationsReleasedAt: DateTime(2026, 9, 23, 11),
    verdict: verdict,
  );
  await _writeEvaluation(db, 'p1', 100,
      name: 'Dr. Panelist One', comments: const {'title': 'Narrow it.'});
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
/// surface -- the repo's own idiom, see `useTallSurface` in
/// `evaluation_screen_test.dart`.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('before release it shows the count and no scores',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submittedCount')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('submittedCount'))).data,
        '1 of 2 panelists have submitted');
    expect(find.byKey(const Key('gradesTable')), findsNothing);
  });

  // D40's mitigation. The count is on the button, so releasing early is a
  // visible choice rather than an accident.
  testWidgets('the release button carries the count', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('Release 1 of 2 evaluations'), findsOneWidget);
  });

  // Ruling 2: before release, a panelist NEVER opens the evaluations list
  // (the rules still deny it to them), so they see only whether THEY have
  // submitted -- never a count of others, and never the release control.
  testWidgets(
      'before release a panelist sees only their own submission status',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedWithOne(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mySubmissionStatus')), findsOneWidget);
    expect(find.byKey(const Key('submittedCount')), findsNothing);
    expect(find.byKey(const Key('releaseEvaluations')), findsNothing);
  });

  testWidgets('after release the table shows every panelist\'s total',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gradesTable')), findsOneWidget);
    expect(find.byKey(const Key('panelMean')), findsOneWidget);
  });

  // Fourteen columns overflow every phone and most laptops. The table has
  // always scrolled; what it lacked was any SIGN of it, so the last
  // criteria simply looked cut off. These two pin both halves.
  testWidgets('the grades table scrolls sideways to reach the last columns',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    // `.first` is the INNERMOST ancestor -- PageShell wraps the whole page
    // in its own vertical SingleChildScrollView, so an unqualified finder
    // matches two and would assert against the wrong axis.
    final view = find
        .ancestor(
          of: find.byKey(const Key('gradesTable')),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    expect(view, findsOneWidget);

    final before = tester.widget<SingleChildScrollView>(view).controller!;
    expect(before.offset, 0);

    await tester.drag(view, const Offset(-300, 0));
    await tester.pumpAndSettle();

    // A table that fit its surface would have nowhere to go, so a non-zero
    // offset is also the assertion that it genuinely overflows.
    expect(before.offset, greaterThan(0));
  });

  testWidgets('the table carries an always-visible scrollbar', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedReleased(), 'p1'));
    await tester.pumpAndSettle();

    final bar = tester.widget<Scrollbar>(find.ancestor(
      of: find.byKey(const Key('gradesTable')),
      matching: find.byType(Scrollbar),
    ).first);

    expect(bar.thumbVisibility, isTrue);
    // Same controller as the view it decorates -- a Scrollbar wired to a
    // different one shows a thumb that never moves.
    expect(
      bar.controller,
      same(tester
          .widget<SingleChildScrollView>(find
              .ancestor(
                of: find.byKey(const Key('gradesTable')),
                matching: find.byType(SingleChildScrollView),
              )
              .first)
          .controller),
    );
  });

  testWidgets('the panel mean is the mean of the submitted totals',
      (tester) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 50.
    await tester.pumpWidget(app(await seedReleased(second: 50), 'p1'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('panelMean'))).data,
        '75.0');
  });

  // .round() rendered 83.5 and 84.4 identically, on the one number the
  // panel deliberates over.
  testWidgets('the panel mean keeps a decimal place', (tester) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 67 -- a mean of 83.5.
    await tester.pumpWidget(app(await seedReleased(second: 67), 'p1'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('panelMean'))).data,
        '83.5');
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
    final storedScores = ((await db
                .collection('defenses')
                .doc('d1')
                .collection('evaluations')
                .doc('p1')
                .get())
            .data()!['scores'] as Map)
        .cast<String, int>();

    final table =
        tester.widget<DataTable>(find.byKey(const Key('gradesTable')));
    final row = table.rows.firstWhere((r) =>
        ((r.cells.first.child as Text).data ?? '') == 'Dr. Panelist One');
    for (var i = 0; i < evaluationCriteria.length; i++) {
      final c = evaluationCriteria[i];
      expect((row.cells[i + 1].child as Text).data, '${storedScores[c.key]}',
          reason: c.key);
      // A perfect sheet, so each column carries its own DIFFERENT weight:
      // a cell wired to the wrong criterion would show as a mismatch
      // rather than coincide.
      expect(storedScores[c.key], c.weight, reason: c.key);
    }
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
  // someone -- the uid is a poor identity but it is not a blank cell.
  testWidgets('a sheet with no stored name falls back to the uid',
      (tester) async {
    useTallSurface(tester);
    final db = await _seedDefence(
        evaluationsReleasedAt: DateTime(2026, 9, 23, 11));
    await _writeEvaluation(db, 'p1', 100);
    await tester.pumpWidget(app(db, 'p1'));
    await tester.pumpAndSettle();

    expect(find.text('p1'), findsOneWidget);
  });

  // Finding 5. The count alone does not tell the adviser WHO is missing,
  // which is what makes releasing at 2 of 3 a considered choice.
  testWidgets('before release the adviser sees who has submitted, by name',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedWithOne(), 'a1'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('submittedNames'))).data,
        'Dr. Panelist One');
  });

  testWidgets('with nobody submitted there is no roster, only the count',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submittedNames')), findsNothing);
  });

  testWidgets('the adviser records the verdict after release',
      (tester) async {
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

  // D42: the adviser is visibly the scribe.
  testWidgets('a recorded verdict names who recorded it', (tester) async {
    useTallSurface(tester);
    await tester
        .pumpWidget(app(await seedReleased(verdict: 'pass'), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verdict')), findsOneWidget);
    // "the adviser", never a uid: the rules pin verdictRecordedBy to the
    // writer's own uid on the only arm that can set it, and only the
    // adviser passes that arm, so the role IS the identity here.
    final scribe =
        tester.widget<Text>(find.byKey(const Key('verdictScribe'))).data!;
    expect(scribe, contains('Recorded by the adviser'));
    expect(scribe, isNot(contains('a1')));
    // The spec wants the timestamp beside the scribe; it was never shown.
    expect(scribe, contains('23/9/2026'));
    expect(find.byKey(const Key('recordVerdict')), findsNothing);
  });

  testWidgets('no evaluations yet says so, and does not look like a zero',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pumpAndSettle();

    expect(
        tester.widget<Text>(find.byKey(const Key('submittedCount'))).data,
        '0 of 2 panelists have submitted');
    expect(find.byKey(const Key('panelMean')), findsNothing);
  });

  // pump() once, NOT pumpAndSettle -- settling resolves the stream and the
  // assertion becomes vacuous.
  testWidgets('shows a loading state before the defence resolves',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seedNone(), 'a1'));
    await tester.pump();

    expect(find.byKey(const Key('gradesLoading')), findsOneWidget);
  });
}
