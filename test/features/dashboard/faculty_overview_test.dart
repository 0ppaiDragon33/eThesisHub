import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/features/dashboard/overview_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Same shape as `thesis()` in navigation_test.dart -- every field
/// `Thesis.fromMap` requires, so a seeded document reads back cleanly.
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

/// Drives the REAL router, wide enough for the shell's rail to render.
///
/// Two of the cases below are about the shell rather than the overview
/// body — that Overview is the first destination, and that the mode switch
/// swaps the tiles — and neither lives inside [FacultyOverview] any more.
/// The destinations moved to the one shell around every signed-in route,
/// and the Adviser/Panelist switch moved into that shell's trailing slot
/// from the deleted faculty dashboard's app bar. Pumping the body alone
/// could no longer see either, so these go through the router, which is
/// also where a reader meets them.
Future<ProviderContainer> routedContainer(
  FakeFirebaseFirestore db, {
  required String uid,
  required String role,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test User',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  return ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    sharedPrefsProvider.overrideWithValue(prefs),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
}

Future<void> pumpRouted(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
  await tester.pumpAndSettle();
}

/// Same shape as `wrap()` in navigation_test.dart, with an `overrides` hook
/// so a test can force the effective mode or replace a stream directly.
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
    'fullName': 'Test User',
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

void main() {
  testWidgets('a Conforme request shows in the queue while in ADVISER mode',
      (tester) async {
    // Spec D17. Testing only the mode a given item "belongs" to would pass
    // with a mode filter left in the provider, and the person who needs to
    // see the request would never find it -- they have no reason to think
    // of looking in the other mode.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await db.collection('theses/t2/nominations').doc('f1').set({
      'nomineeUid': 'f1',
      'nomineeName': 'Dr. F',
      'position': 'panelist',
      'exOfficio': false,
      'conformeStatus': 'pending',
      'respondedAt': null,
      'declineReason': null,
    });
    await db.collection('theses').doc('t2').set(thesis(adviserUid: 'other'));

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'f1',
      role: 'faculty',
    ));
    await tester.pumpAndSettle();

    // f1 advises t1, so effectiveFacultyModeProvider clamps to adviser mode.
    expect(find.text('Reply'), findsOneWidget);
  });

  testWidgets('a chapter to review shows in the queue while in PANELIST mode',
      (tester) async {
    // The mirror of the test above. Both directions, or the assertion is
    // satisfied by a filter that happens to match one case.
    final db = FakeFirebaseFirestore();
    // f2 sits on t3's panel, holding no advisee there.
    await db.collection('theses').doc('t3').set(thesis(adviserUid: 'other'));
    await db.collection('theses/t3/nominations').doc('f2').set({
      'nomineeUid': 'f2',
      'conformeStatus': 'accepted',
    });
    // f2 also advises t4, which has a chapter waiting on their review.
    await db.collection('theses').doc('t4').set(thesis(adviserUid: 'f2'));
    await db
        .collection('theses/t4/documents')
        .doc('chapterI')
        .set({'currentVersion': 1, 'status': 'submitted'});

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'f2',
      role: 'faculty',
      overrides: [
        // f2 holds both positions, so the stored preference (unset) would
        // otherwise default to adviser mode. Forcing panelist mode here is
        // the point of the test: the chapter still needing review lives on
        // an ADVISED thesis, and the queue must show it anyway.
        effectiveFacultyModeProvider
            .overrideWith((ref) async => FacultyMode.panelist),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('the overview is the first destination', (tester) async {
    // Through the router now: the destinations live in the shell, not in
    // a dashboard, so a bare widget pump can no longer see them. The
    // property is unchanged — a faculty member LANDS on the overview, and
    // Overview is the first thing the sidebar offers. Landing on a work
    // queue was the complaint the previous milestone existed to answer.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));

    final c = await routedContainer(db, uid: 'a1', role: 'faculty');
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    expect(find.byKey(const Key('facultyOverview')), findsOneWidget);
    final rail = find.byType(NavigationRail);
    expect(find.descendant(of: rail, matching: find.text('Overview')),
        findsOneWidget);
    final destinations = tester
        .widget<NavigationRail>(rail)
        .destinations
        .map((d) => (d.label as Text).data)
        .toList();
    expect(destinations.first, 'Overview');
  });

  testWidgets('the tiles change with the mode switch', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f3'));
    await db.collection('theses').doc('t2').set(thesis(adviserUid: 'other'));
    await db.collection('theses/t2/nominations').doc('f3').set({
      'nomineeUid': 'f3',
      'conformeStatus': 'accepted',
    });

    // Through the router: the Adviser/Panelist switch moved out of the
    // deleted faculty dashboard's app bar and into the shell's trailing
    // slot, so it is only present when the shell is.
    final c = await routedContainer(db, uid: 'f3', role: 'faculty');
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    // f3 holds both positions. The stored preference is unset, which
    // defaults to adviser mode -- so the tile row shows the adviser's
    // figures, including its own "Advisees" tile (in addition to the nav
    // destination of the same name).
    expect(find.text('Advisees'), findsWidgets);
    expect(find.text('Chapters awaiting your review'), findsOneWidget);
    expect(find.text('Panels'), findsNothing);

    await tester.tap(find.text('Panelist'));
    await tester.pumpAndSettle();

    // Switching modes swaps the tile row entirely -- the queue underneath
    // is untouched by this (covered by the two tests above), but the tiles
    // must change.
    expect(find.text('Panels'), findsWidgets);
    expect(find.text('Title sets to review'), findsOneWidget);
    expect(find.text('Advisees'), findsNothing);
  });

  testWidgets('a loading queue is distinguishable from an empty one',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'a1',
      role: 'faculty',
      overrides: [
        // The mode is resolved up front so this test isolates the queue's
        // own stream, the same reasoning `my_advisees_test.dart` uses for
        // its analogous loading-branch test.
        effectiveFacultyModeProvider
            .overrideWith((ref) async => FacultyMode.adviser),
        // A stream that never emits, so the queue's own loading branch is
        // genuinely observable rather than settling into "All caught up".
        facultyNeedsYouProvider.overrideWith(
            (ref) => StreamController<List<NeedsYouItem>>().stream),
      ],
    ));
    // Deliberately a single pump, never pumpAndSettle: this must catch the
    // loading branch before the (never-emitting) stream's first snapshot,
    // not the empty-list branch that a collapsed `data(const [])` would be
    // indistinguishable from -- the single most repeated bug in this
    // codebase.
    await tester.pump();

    expect(find.text('Checking what needs you…'), findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
  });
}
