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
import 'package:ethesishub/features/dashboard/dean_overview.dart';
import 'package:ethesishub/features/dashboard/overview_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
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
  Widget dashboard,
  FakeFirebaseFirestore db, {
  required String uid,
  required String role,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test Dean',
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

/// For the one case below that has to go through the real router: the
/// sidebar destinations live in the app shell now, and a bare widget pump
/// cannot see them.
Future<ProviderContainer> containerFor(String role, String uid) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc(uid).set({
    'fullName': 'Test Dean',
    'email': '$uid@isufst.edu.ph',
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
      mockUser: MockUser(
          uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
}

void main() {
  testWidgets('the dean lands on the overview, not the approvals list',
      (tester) async {
    // Through the router, and wide: the destinations moved out of the
    // deleted dean dashboard into the one app shell, which renders them as
    // a rail above 900px. What is asserted is unchanged.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await containerFor('dean', 'd1');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    // The complaint this task answers: the dean landed on the approvals
    // queue with nothing summarising the college around it.
    expect(find.byKey(const Key('deanOverview')), findsOneWidget);
    expect(find.text('Nomination approvals'), findsNothing);

    final rail = find.byType(NavigationRail);
    expect(find.descendant(of: rail, matching: find.text('Overview')),
        findsOneWidget);
  });

  testWidgets(
      'a thesis awaiting the dean\'s approval appears in the queue',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(thesis(status: 'nominationPendingDean'));

    await tester.pumpWidget(
        await wrap(const OverviewScreen(), db, uid: 'd1', role: 'dean'));
    await tester.pumpAndSettle();

    expect(find.text('A Working Title'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('both college-wide chart panels are present', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
        await wrap(const OverviewScreen(), db, uid: 'd1', role: 'dean'));
    await tester.pumpAndSettle();

    expect(find.text('Theses by stage'), findsOneWidget);
    expect(find.textContaining('Past 7 months'), findsOneWidget);
  });

  testWidgets('the four tiles render', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
        await wrap(const OverviewScreen(), db, uid: 'd1', role: 'dean'));
    await tester.pumpAndSettle();

    expect(find.text('Awaiting your approval'), findsOneWidget);
    expect(find.text('Title defences'), findsOneWidget);
    expect(find.text('Defences this week'), findsOneWidget);
    expect(find.text('Active theses'), findsOneWidget);
  });

  testWidgets('a loading queue is distinguishable from an empty one',
      (tester) async {
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'd1',
      role: 'dean',
      overrides: [
        // A stream that never emits, so the queue's own loading branch is
        // genuinely observable rather than settling into "All caught up".
        deanNeedsYouProvider.overrideWith(
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
    //
    // Pumped as [DeanOverview] rather than through [OverviewScreen], which
    // is the widget whose whole job is to pick an overview BY role and
    // which correctly renders nothing once the role has settled as unknown
    // — an account with no profile is routed to /no-profile now (spec
    // D25), so asking the role dispatcher to show a dean's overview
    // without a role would assert the opposite of what the app does. The
    // property under test is this overview's own.
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(
        await wrap(const DeanOverview(), db, uid: 'd1', role: 'dean'));
    // Remove the profile the helper wrote.
    await db.collection('users').doc('d1').delete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deanOverview')), findsOneWidget);
    expect(find.textContaining('Good'), findsOneWidget);
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

    // [DeanOverview] directly, for the same reason as the greeting test
    // above: the role dispatcher renders nothing for a settled-unknown
    // role by design, so it cannot host a no-profile test.
    await tester.pumpWidget(
        await wrap(const DeanOverview(), db, uid: 'd1', role: 'dean'));
    // Remove the profile the helper wrote -- the same missing-document
    // window the greeting test exercises, but checked against the tile
    // instead of the greeting.
    await db.collection('users').doc('d1').delete();
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
