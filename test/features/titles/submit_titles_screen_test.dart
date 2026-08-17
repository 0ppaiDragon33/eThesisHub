import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/features/titles/submit_titles_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded({
  String status = 'nominationApproved',
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': status, 'panelistUids': <String>[],
    'adviserUid': 'a1', 'memberNames': <String>[], 'workingTitle': 'T',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027', 'titleRound': 0,
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1', email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/thesis/titles',
          routes: [
            GoRoute(
              path: '/thesis/titles',
              builder: (_, _) => const SubmitTitlesScreen(thesisId: 't1'),
            ),
            GoRoute(
              path: '/thesis',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('status', key: Key('landedOnStatus'))),
              ),
            ),
          ],
        ),
      ),
    );

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opens with three candidate slots', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleText0')), findsOneWidget);
    expect(find.byKey(const Key('titleText1')), findsOneWidget);
    expect(find.byKey(const Key('titleText2')), findsOneWidget);
  });

  testWidgets('refuses to submit with a blank title', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitTitles')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('title'));
    expect((await db.collection('theses/t1/candidateTitles').get()).docs,
        isEmpty);
  });

  testWidgets('refuses to submit without a justification for every title',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byKey(Key('titleText$i')), 'Candidate $i');
    }
    await tester.tap(find.byKey(const Key('submitTitles')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('justification'));
    expect((await db.collection('theses/t1/candidateTitles').get()).docs,
        isEmpty);
  });

  testWidgets('caps the candidates and says why', (tester) async {
    // Ten is a rules constraint, not a preference: each candidate costs a
    // get() and M1a measured that a batch of 20 is denied.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    for (var i = 3; i < 10; i++) {
      await tester.tap(find.byKey(const Key('addCandidate')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('titleText9')), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('addCandidate')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('candidateCapReason')), findsOneWidget);
  });

  testWidgets('refuses when the thesis is not ready for a submission',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded(status: 'draft')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notReady')), findsOneWidget);
    expect(find.byKey(const Key('submitTitles')), findsNothing);
  });
}
