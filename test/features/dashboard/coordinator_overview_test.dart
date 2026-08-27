import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/app.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/features/dashboard/coordinator_overview.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

// Same shape as dean_overview_test.dart's own copy -- every field
// `Thesis.fromMap` requires, so a seeded document reads back cleanly.
Map<String, dynamic> thesis({
  String workingTitle = 'A Working Title',
  String leaderUid = 'l1',
  String adviserUid = 'a1',
  String status = 'titleApproved',
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': adviserUid,
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': workingTitle,
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

Future<Widget> wrap(
  Widget dashboard,
  FakeFirebaseFirestore db, {
  required String uid,
  required String role,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test Coordinator',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
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
    child: MaterialApp(home: dashboard),
  );
}

Future<ProviderContainer> containerFor(String role, String uid,
    {FakeFirebaseFirestore? db}) async {
  final firestore = db ?? FakeFirebaseFirestore();
  await firestore.collection('users').doc(uid).set({
    'fullName': 'Test',
    'email': 't@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    firestoreProvider.overrideWithValue(firestore),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser:
          MockUser(uid: uid, email: 't@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
}

void main() {
  testWidgets(
      'the coordinator lands on the overview, not the recommendations list',
      (tester) async {
    // Through the router, and wide: the destinations moved out of the
    // deleted coordinator dashboard into the one app shell, which renders
    // them as a rail above 900px. What is asserted is unchanged — the
    // coordinator LANDS on the overview rather than a work list, and
    // Overview is offered in the navigation.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await containerFor('coordinator', 'c1');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coordinatorOverview')), findsOneWidget);
    expect(find.text('Nomination recommendations'), findsNothing);

    final rail = find.byType(NavigationRail);
    expect(find.descendant(of: rail, matching: find.text('Overview')),
        findsOneWidget);
  });

  testWidgets(
      'a thesis awaiting the coordinator\'s recommendation appears in the '
      'queue', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(thesis(status: 'nominationPendingCoordinator'));

    await tester.pumpWidget(await wrap(const CoordinatorOverview(), db,
        uid: 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();

    expect(find.text('A Working Title'), findsWidgets);
    expect(find.text('Recommend'), findsOneWidget);
  });

  testWidgets('both college-wide chart panels are present', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(await wrap(const CoordinatorOverview(), db,
        uid: 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();

    expect(find.text('Theses by stage'), findsOneWidget);
    expect(find.textContaining('Past 7 months'), findsOneWidget);
  });

  testWidgets('the four tiles render', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(await wrap(const CoordinatorOverview(), db,
        uid: 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();

    expect(find.text('Active theses'), findsOneWidget);
    expect(find.text('Awaiting your recommendation'), findsOneWidget);
    expect(find.text('Defences this week'), findsOneWidget);
    expect(find.text('Faculty accounts'), findsOneWidget);
  });

  testWidgets('a loading queue is distinguishable from an empty one',
      (tester) async {
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(await wrap(
      const CoordinatorOverview(),
      db,
      uid: 'c1',
      role: 'coordinator',
      overrides: [
        // A stream that never emits, so the queue's own loading branch is
        // genuinely observable rather than settling into "All caught up".
        coordinatorNeedsYouProvider.overrideWith(
            (ref) => StreamController<List<NeedsYouItem>>().stream),
      ],
    ));
    // Deliberately a single pump, never pumpAndSettle: this must catch the
    // loading branch before the (never-emitting) stream's first snapshot,
    // not the empty-list branch that a collapsed `data(const [])` would be
    // indistinguishable from.
    await tester.pump();

    expect(find.text('Checking what needs you…'), findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
  });

  testWidgets('the greeting survives a missing profile document',
      (tester) async {
    // An earlier milestone shipped a lockout by gating on the profile doc.
    // Nothing on an overview may depend on `users/{uid}` existing.
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(await wrap(const CoordinatorOverview(), db,
        uid: 'c1', role: 'coordinator'));
    // Remove the profile the helper wrote.
    await db.collection('users').doc('c1').delete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coordinatorOverview')), findsOneWidget);
    expect(find.textContaining('Good'), findsOneWidget);
  });

  testWidgets('the table orders by working title, not by insertion',
      (tester) async {
    // fake_cloud_firestore returns documents in insertion order, so the
    // fixture is seeded AGAINST the expected order. Seeded alphabetically,
    // this test would pass with the sort deleted -- exactly how a vacuous
    // ordering test slipped through an earlier milestone.
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(thesis(workingTitle: 'Zebra', status: 'draft'));
    await db
        .collection('theses')
        .doc('t2')
        .set(thesis(workingTitle: 'Alpha', status: 'draft'));

    await tester.pumpWidget(await wrap(const CoordinatorOverview(), db,
        uid: 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Zebra'));
    await tester.pumpAndSettle();

    final alphaDy = tester.getTopLeft(find.text('Alpha')).dy;
    final zebraDy = tester.getTopLeft(find.text('Zebra')).dy;
    expect(alphaDy, lessThan(zebraDy));
  });

  testWidgets('a filter tab narrows the table', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(thesis(workingTitle: 'Chaptered Thesis', status: 'titleApproved'));
    await db
        .collection('theses')
        .doc('t2')
        .set(thesis(workingTitle: 'Draft Thesis', status: 'draft'));

    await tester.pumpWidget(await wrap(const CoordinatorOverview(), db,
        uid: 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Chaptered Thesis'));
    expect(find.text('Chaptered Thesis'), findsOneWidget);
    expect(find.text('Draft Thesis'), findsOneWidget);

    final draftTab = find.byKey(const Key('thesesFilter-draft'));
    await tester.ensureVisible(draftTab);
    await tester.tap(draftTab);
    await tester.pumpAndSettle();

    // A titleApproved (Chapters-stage) thesis disappears once the Draft
    // filter narrows the table.
    expect(find.text('Chaptered Thesis'), findsNothing);
    expect(find.text('Draft Thesis'), findsOneWidget);
  });

  testWidgets(
      'the Faculty destination still reaches /invites after the Overview '
      'shift', (tester) async {
    // Prepending Overview shifted every other coordinator destination's
    // index by one -- Faculty moved from index 4 to index 5. The dashboard
    // used to jump on a hard-coded `if (i == 4)`, which would have silently
    // routed this exact tap (now index 5) to whatever destination 4
    // (Readiness) renders instead, with no error. The index literal is
    // gone with the dashboard, but the property it guarded is not: tapping
    // Faculty must reach the invites screen and nothing else.
    //
    // Wide on purpose. The destinations live in the app shell now, which
    // shows them as a rail above 900px and behind a hamburger below it —
    // the default 800px test surface would leave the drawer shut and the
    // tap would find nothing.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await containerFor('coordinator', 'c1');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('Faculty')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('facultyInvitesScreen')), findsOneWidget);
    expect(find.text('Defence readiness'), findsNothing);
  });

  testWidgets(
      'the Defences this week tile still shows the college-wide count '
      'without a profile document', (tester) async {
    // myDefencesProvider awaits currentUserProvider.future and branches on
    // role -- with no `users/{uid}` document, that branch does not match
    // the dean/coordinator arm, and it silently falls through to the
    // faculty adviser/panel fan-in instead of watchAll(). Nothing hangs,
    // so the earlier "greeting survives a missing profile" test cannot
    // catch this: the tile just quietly shows the wrong count. This pins
    // `allDefencesProvider` as the fix.
    final db = FakeFirebaseFirestore();
    final today = DateTime.now();
    await db.collection('defenses').doc('def1').set({
      'thesisId': 't1',
      'type': 'preOral',
      'scheduledAt': Timestamp.fromDate(today),
      'venue': 'CICT AVR',
      'panelUids': <String>[],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'scheduled',
      'createdBy': 'c1',
    });

    await tester.pumpWidget(await wrap(const CoordinatorOverview(), db,
        uid: 'c1', role: 'coordinator'));
    // Remove the profile the helper wrote -- the same missing-document
    // window the greeting test exercises, but checked against the tile
    // instead of the greeting.
    await db.collection('users').doc('c1').delete();
    await tester.pumpAndSettle();

    final tile = find.ancestor(
        of: find.text('Defences this week'), matching: find.byKey(const Key('statTilePadding')));
    expect(find.descendant(of: tile, matching: find.text('1')),
        findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('0')),
        findsNothing);
    expect(find.descendant(of: tile, matching: find.text('—')),
        findsNothing);
  });
}
