import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/features/dashboard/advisees_screen.dart';
import 'package:ethesishub/features/dashboard/approvals_screen.dart';
import 'package:ethesishub/features/dashboard/overview_screen.dart';
import 'package:ethesishub/features/dashboard/panels_screen.dart';
import 'package:ethesishub/features/dashboard/readiness_screen.dart';
import 'package:ethesishub/features/dashboard/recommendations_screen.dart';
import 'package:ethesishub/features/dashboard/title_defences_screen.dart';
import 'package:ethesishub/features/defence/defences_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

// Same shape as navigation_test.dart's own copy -- every field
// `Thesis.fromMap` requires, so a seeded document reads back cleanly.
Map<String, dynamic> thesis({
  String leaderUid = 'l1',
  String adviserUid = 'a1',
  String status = 'titleApproved',
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': adviserUid,
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': 'A Working Title',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

Future<Widget> wrap(
  Widget screen,
  FakeFirebaseFirestore db, {
  required String uid,
  required String role,
  bool seedProfile = true,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  if (seedProfile) {
    await db.collection('users').doc(uid).set({
      'fullName': 'Test User',
      'email': '$uid@isufst.edu.ph',
      'role': role,
      'active': true,
    });
  }
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
      ...overrides,
    ],
    // Each screen renders no Scaffold/Material of its own -- the app shell
    // owns that. Standing one up here is what `MaterialApp(home: dashboard)`
    // got for free from `ResponsiveScaffold` in the dashboard-level harness.
    child: MaterialApp(home: Scaffold(body: screen)),
  );
}

void main() {
  testWidgets('overview screen renders the student overview standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
          thesis(leaderUid: 'u1'),
        );

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'u1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
  });

  testWidgets('defences screen renders the defences list standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(await wrap(
      const DefencesScreen(),
      db,
      uid: 'u1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defencesScreen')), findsOneWidget);
    expect(find.text('Scheduled defences'), findsOneWidget);
  });

  testWidgets('advisees screen renders the adviser roster standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
          thesis(adviserUid: 'f1'),
        );

    await tester.pumpWidget(await wrap(
      const AdviseesScreen(),
      db,
      uid: 'f1',
      role: 'faculty',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adviseesScreen')), findsOneWidget);
    expect(find.text('A Working Title'), findsOneWidget);
  });

  testWidgets('panels screen renders the panel roster standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
          thesis(status: 'titlePendingDefence')
            ..addAll({
              'panelistUids': ['f1'],
            }),
        );

    await tester.pumpWidget(await wrap(
      const PanelsScreen(),
      db,
      uid: 'f1',
      role: 'faculty',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('panelsScreen')), findsOneWidget);
    expect(find.text('My panels'), findsOneWidget);
  });

  testWidgets('approvals screen renders the dean queue standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
          thesis(status: 'nominationPendingDean'),
        );

    await tester.pumpWidget(await wrap(
      const ApprovalsScreen(),
      db,
      uid: 'd1',
      role: 'dean',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approvalsScreen')), findsOneWidget);
    expect(find.text('A Working Title'), findsOneWidget);
  });

  testWidgets(
      'recommendations screen renders the coordinator queue standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
          thesis(status: 'nominationPendingCoordinator'),
        );

    await tester.pumpWidget(await wrap(
      const RecommendationsScreen(),
      db,
      uid: 'c1',
      role: 'coordinator',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recommendationsScreen')), findsOneWidget);
    expect(find.text('A Working Title'), findsOneWidget);
  });

  testWidgets('title defences screen renders the defence queue standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
          thesis(status: 'titlePendingDefence'),
        );

    await tester.pumpWidget(await wrap(
      const TitleDefencesScreen(),
      db,
      uid: 'd1',
      role: 'dean',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleDefencesScreen')), findsOneWidget);
    expect(find.text('Title defences'), findsOneWidget);
  });

  testWidgets('readiness screen renders the readiness list standalone',
      (tester) async {
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(await wrap(
      const ReadinessScreen(),
      db,
      uid: 'd1',
      role: 'dean',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readinessScreen')), findsOneWidget);
    expect(find.text('Defence readiness'), findsOneWidget);
  });

  testWidgets('the overview screen never guesses a role', (tester) async {
    // Spec D25. With no users/{uid} document, this must render no
    // dashboard at all rather than falling through to a default.
    final db = FakeFirebaseFirestore(); // no profile seeded
    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'u1',
      role: 'student',
      seedProfile: false,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('studentOverview')), findsNothing);
    expect(find.byKey(const Key('facultyOverview')), findsNothing);
    expect(find.byKey(const Key('deanOverview')), findsNothing);
    expect(find.byKey(const Key('coordinatorOverview')), findsNothing);
  });
}
