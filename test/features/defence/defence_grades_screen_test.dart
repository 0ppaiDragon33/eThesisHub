import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
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

Future<void> _writeEvaluation(
  FakeFirebaseFirestore db,
  String uid,
  int total,
) async {
  await db
      .collection('defenses')
      .doc('d1')
      .collection('evaluations')
      .doc(uid)
      .set({
    'scores': const <String, int>{},
    'comments': const <String, String>{},
    'total': total,
    'rating': 'pass',
    'submittedAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9, 30)),
  });
}

/// Panel of p1, p2; only p1 has submitted, and the grades are not yet
/// released.
Future<FakeFirebaseFirestore> seedWithOne() async {
  final db = await _seedDefence();
  await _writeEvaluation(db, 'p1', 100);
  return db;
}

/// Both panelists have submitted and the adviser has released the grades.
Future<FakeFirebaseFirestore> seedReleased({int second = 100, String? verdict}) async {
  final db = await _seedDefence(
    evaluationsReleasedAt: DateTime(2026, 9, 23, 11),
    verdict: verdict,
  );
  await _writeEvaluation(db, 'p1', 100);
  await _writeEvaluation(db, 'p2', second);
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

  testWidgets('the panel mean is the mean of the submitted totals',
      (tester) async {
    useTallSurface(tester);
    // p1 at 100, p2 at 50.
    await tester.pumpWidget(app(await seedReleased(second: 50), 'p1'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('panelMean'))).data,
        '75');
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
    expect(find.byKey(const Key('verdictScribe')), findsOneWidget);
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
