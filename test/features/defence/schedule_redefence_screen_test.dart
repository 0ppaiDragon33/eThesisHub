import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/defence/schedule_redefence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seed({
  String role = 'coordinator',
  String verdict = 'fail',
  String? redefenceOf,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('c1').set({
    'fullName': 'Coordinator',
    'email': 'c1@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1',
    'panelistUids': <String>['p1', 'p2'],
    'memberNames': <String>[], 'workingTitle': 'Mangrove Carbon Stocks',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027', 'status': 'titleApproved',
  });
  await db.collection('defenses').doc('f1').set({
    'thesisId': 't1', 'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
    'venue': 'AVR', 'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
    'createdBy': 'c1', 'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    'panelVerdict': verdict,
    if (redefenceOf != null) 'redefenceOf': redefenceOf,
  });
  return db;
}

Future<GoRouter> pump(WidgetTester tester, FakeFirebaseFirestore db) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/s',
    routes: [
      GoRoute(
        path: '/s',
        builder: (_, _) => const Scaffold(
            body: ScheduleRedefenceScreen(failedDefenceId: 'f1')),
      ),
      GoRoute(
        path: '/defence/room/:id',
        builder: (_, s) =>
            Scaffold(body: Text('room ${s.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'c1', email: 'c1@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('says which defence is re-defended, and schedules it',
      (tester) async {
    final db = await seed();
    await pump(tester, db);

    expect(find.byKey(const Key('redefenceOfSummary')), findsOneWidget);
    expect(find.textContaining('Re-defence of the final defence held'),
        findsOneWidget);

    await tester.enterText(find.byKey(const Key('redefenceVenue')), 'AVR 2');
    await tester.tap(find.byKey(const Key('scheduleRedefenceButton')));
    await tester.pumpAndSettle();

    final again = await db.doc('defenses/f1_redefence').get();
    expect(again.exists, isTrue);
    expect(again.data()!['redefenceOf'], 'f1');
    expect(again.data()!['type'], 'final');
    expect(find.text('room f1_redefence'), findsOneWidget);
  });

  testWidgets('a passed defence cannot be re-defended', (tester) async {
    final db = await seed(verdict: 'pass');
    await pump(tester, db);
    expect(find.byKey(const Key('cannotRedefend')), findsOneWidget);
    expect(find.byKey(const Key('scheduleRedefenceButton')), findsNothing);
  });

  testWidgets('a re-defence cannot be re-defended', (tester) async {
    final db = await seed(redefenceOf: 'f0');
    await pump(tester, db);
    expect(find.byKey(const Key('cannotRedefend')), findsOneWidget);
  });

  testWidgets('a defence already re-defended cannot be again',
      (tester) async {
    final db = await seed();
    await db.doc('defenses/f1_redefence').set({
      ...(await db.doc('defenses/f1').get()).data()!,
      'status': 'scheduled',
      'redefenceOf': 'f1',
    });
    await pump(tester, db);
    expect(find.byKey(const Key('cannotRedefend')), findsOneWidget);
  });

  testWidgets('a blank venue is refused with the reason', (tester) async {
    final db = await seed();
    await pump(tester, db);
    await tester.tap(find.byKey(const Key('scheduleRedefenceButton')));
    await tester.pumpAndSettle();
    expect(find.text('Give the re-defence a venue.'), findsOneWidget);
  });

  testWidgets('only the Coordinator gets the button', (tester) async {
    final db = await seed(role: 'faculty');
    await pump(tester, db);
    expect(find.byKey(const Key('scheduleRedefenceButton')), findsNothing);
    expect(find.text('Only the Research Coordinator can schedule defences.'),
        findsOneWidget);
  });
}
