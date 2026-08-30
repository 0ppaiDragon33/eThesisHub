import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/features/defence/evaluation_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seed({
  String status = 'completed',
  DateTime? releasedAt,
  Map<String, int>? existing,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1', 'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR', 'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1', 'leaderUid': 'l1', 'status': status,
    'createdBy': 'c1',
    if (releasedAt != null)
      'evaluationsReleasedAt': Timestamp.fromDate(releasedAt),
  });
  if (existing != null) {
    await db
        .collection('defenses').doc('d1')
        .collection('evaluations').doc('p1')
        .set({
      'scores': existing,
      'comments': const <String, String>{},
      'total': existing.values.fold<int>(0, (a, b) => a + b),
      'rating': 'pass',
    });
  }
  return db;
}

Widget app(FakeFirebaseFirestore db, String uid) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: EvaluationScreen(defenceId: 'd1')),
    ),
  );
}

void main() {
  testWidgets('renders every criterion of Form 5c', (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    for (final c in evaluationCriteria) {
      expect(find.byKey(Key('score_${c.key}')), findsOneWidget,
          reason: c.key);
    }
  });

  testWidgets('only Content criteria carry a comment field',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comment_title')), findsOneWidget);
    expect(find.byKey(const Key('comment_alertness')), findsNothing);
  });

  testWidgets('the running total sums the scores as they change',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('finalGrade')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('finalGrade'))).data, '0');

    await tester.tap(find.byKey(const Key('plus_title')));
    await tester.pump();
    expect(
        tester.widget<Text>(find.byKey(const Key('finalGrade'))).data, '1');
  });

  // D34's mitigation: eleven different maximums, so the control refuses
  // out-of-range rather than accepting then rejecting it.
  testWidgets('a stepper clamps at zero and at its own weight',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    // recommendation is worth 2 -- three taps must not reach 3.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('plus_recommendation')));
      await tester.pump();
    }
    expect(
        tester
            .widget<Text>(find.byKey(const Key('score_recommendation')))
            .data,
        '2');

    await tester.tap(find.byKey(const Key('minus_title')));
    await tester.pump();
    expect(
        tester.widget<Text>(find.byKey(const Key('score_title'))).data, '0');
  });

  testWidgets('submit is disabled until every criterion is scored',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submitEvaluation')))
            .onPressed,
        isNull);
  });

  testWidgets('an existing sheet loads its scores back', (tester) async {
    final scores = {for (final c in evaluationCriteria) c.key: c.weight};
    await tester.pumpWidget(app(await seed(existing: scores), 'p1'));
    await tester.pumpAndSettle();

    expect(
        tester.widget<Text>(find.byKey(const Key('finalGrade'))).data, '100');
  });

  testWidgets('a released evaluation is read-only', (tester) async {
    final scores = {for (final c in evaluationCriteria) c.key: c.weight};
    await tester.pumpWidget(app(
        await seed(existing: scores, releasedAt: DateTime(2026, 9, 23)),
        'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('submitEvaluation')), findsNothing);
    expect(find.byKey(const Key('releasedNotice')), findsOneWidget);
  });

  testWidgets('the adviser is told they do not score', (tester) async {
    await tester.pumpWidget(app(await seed(), 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adviserRefusal')), findsOneWidget);
    expect(find.byKey(const Key('submitEvaluation')), findsNothing);
  });

  // The distinction D41 depends on staying visible.
  testWidgets('the panelist rating is labelled as their own, not the panel\'s',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ratingIsYours')), findsOneWidget);
  });

  // pump() once, NOT pumpAndSettle -- settling resolves the stream and
  // the assertion becomes vacuous.
  testWidgets('shows a loading state before the defence resolves',
      (tester) async {
    await tester.pumpWidget(app(await seed(), 'p1'));
    await tester.pump();

    expect(find.byKey(const Key('evaluationLoading')), findsOneWidget);
  });
}
