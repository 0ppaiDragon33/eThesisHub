import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/features/dashboard/advisees_screen.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Seeds two theses: one advised by `a1`, one advised by `other`. Each has
/// the fields `Thesis.fromMap` requires, matching the shape written by
/// `ThesisRepository.approve` in production.
Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('mine').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'My Advised Thesis', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  await db.collection('theses').doc('notMine').set({
    'leaderUid': 'l2', 'adviserUid': 'other', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'Someone Elses Thesis', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
  });
  return db;
}

/// Without this, `FirebaseAuth.instance` throws `[core/no-app]` because no
/// app is initialised in a widget test, `authStateProvider` settles into
/// AsyncError, and any uid read off it is silently null forever. See
/// adviser_review_test.dart's `_wrap` for the same pattern. sharedPrefsProvider
/// must also be overridden -- facultyModeProvider reads it on every build,
/// and it throws UnimplementedError unless a value is supplied.
Future<Widget> _wrap(
  FakeFirebaseFirestore db, {
  required String uid,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
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
    child: const MaterialApp(home: Scaffold(body: AdviseesScreen())),
  );
}

void main() {
  testWidgets('an adviser sees only the theses they advise', (tester) async {
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('My Advised Thesis'), findsOneWidget);
    expect(find.text('Someone Elses Thesis'), findsNothing);
  });

  testWidgets('the placeholder copy is gone', (tester) async {
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    // Shipped for two milestones, promising a list that could not exist
    // until the adviser arm on `allow list` (theses) landed. This test is
    // what stops the sentence outliving the feature it was standing in for.
    expect(find.textContaining('Coming with the documents module'),
        findsNothing);
  });

  testWidgets(
      'a newly invited member with no positions gets the mode switch, not '
      'an empty screen and no way out', (tester) async {
    // The reported failure this milestone closes: `FacultyMode.fromString
    // (null)` resolves to adviser, so a newly invited faculty member landed
    // on an empty Advisees list -- and could not leave, because the switch
    // was gated on holding an adviser position, which they never had.
    //
    // A missing `users/{uid}` designation field defaults to `true` for both
    // `nominableAsAdviser` and `nominableAsPanelist` (spec §6): a brand-new
    // account, not yet narrowed by a coordinator, is designated for both.
    // Capability is the union of designation and positions held, so this
    // member is "both capable" even though they hold zero positions --
    // which is exactly the fix: they land on the stored preference
    // (defaulting to Advisees) WITH the switch, rather than being stranded
    // wherever the old position-only clamp happened to put them.
    //
    // Through the REAL router and wide (1000px), because the destinations
    // this asserts on moved out of the deleted faculty dashboard and into
    // the app shell, which shows them as a rail above 900px. What is
    // asserted is unchanged, and it is asserted at the level where the
    // reader actually meets it.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('lonely').set({
      'fullName': 'Newly Invited',
      'email': 'lonely@isufst.edu.ph',
      'role': 'faculty',
      'active': true,
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'lonely',
            email: 'lonely@isufst.edu.ph',
            isEmailVerified: true),
      )),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    // Overview is destination 0 regardless of position; it is the
    // destination AFTER it -- the mode's own work -- that must be Advisees
    // (the stored preference's default), not absent and not a dead end.
    final rail = find.byType(NavigationRail);
    expect(find.descendant(of: rail, matching: find.text('Advisees')),
        findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);

    // And the switch is there, because they can reach both modes -- so
    // Panels is not unreachable even though no position ever put them there.
    expect(find.byKey(const Key('facultyModeSegmented')), findsOneWidget);

    // The switch only re-routes off the mode's OWN screen (`/advisees` or
    // `/panels`); on Overview it would just relabel the rail. Navigate to
    // Advisees first so flipping the switch has somewhere to move FROM.
    await tester
        .tap(find.descendant(of: rail, matching: find.text('Advisees')));
    await tester.pumpAndSettle();
    expect(find.text('My advisees'), findsOneWidget);

    await tester.tap(find.text('Panelist'));
    await tester.pumpAndSettle();
    expect(find.text('My panels'), findsOneWidget);
    expect(find.text('My advisees'), findsNothing);
  });

  testWidgets('the advisee list is loading before the first snapshot arrives',
      (tester) async {
    final db = await _seed();
    // The mode is resolved up front so this test isolates the stream it is
    // actually about. Without it the dashboard-level mode gate renders its
    // own spinner first and the assertion would target the wrong one.
    await tester.pumpWidget(await _wrap(db, uid: 'a1', overrides: [
      effectiveFacultyModeProvider
          .overrideWith((ref) async => FacultyMode.adviser),
      // A stream that never emits, so the loading branch is genuinely
      // observable. fake_cloud_firestore resolves inside a single pump, so
      // a real query cannot hold this frame open long enough to assert on.
      myAdviseesProvider.overrideWith((ref) => StreamController<List<Thesis>>().stream),
    ]));
    // The screen is pumped on its own now rather than reached by tapping a
    // dashboard destination -- '/advisees' is a route of its own, and that
    // it is reachable is asserted in
    // test/core/routing/shell_routes_test.dart. What this test is about is
    // this screen's own handling of an unsettled stream.
    //
    // Deliberately NOT pumpAndSettle: it asserts the loading branch
    // renders before the stream's first snapshot, rather than the
    // empty-list branch. Collapsing loading into an empty data(const [])
    // list would make "still loading" and "no advisees" indistinguishable
    // -- a bug this project has already shipped four times (see the
    // comment on adviseesAsync.when in advisees_screen.dart).
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('My Advised Thesis'), findsNothing);
    expect(find.text('No advisees yet'), findsNothing);
  });

  testWidgets('an advisee row shows a count of chapters awaiting review',
      (tester) async {
    final db = await _seed();
    await db
        .collection('theses/mine/documents')
        .doc('chapterI')
        .set({'currentVersion': 1, 'status': 'submitted'});
    await db
        .collection('theses/mine/documents')
        .doc('chapterII')
        .set({'currentVersion': 1, 'status': 'submitted'});
    await db
        .collection('theses/mine/documents')
        .doc('chapterIII')
        .set({'currentVersion': 1, 'status': 'approved'});

    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('2 chapters awaiting review'), findsOneWidget);
  });

  testWidgets(
      'the awaiting-review count is NOT shown as "0" while its stream is '
      'still loading', (tester) async {
    // Deliberately bare pump()s, never pumpAndSettle: this must observe
    // the chapter stream's loading branch, not its settled state. "0
    // awaiting" and "still loading" are indistinguishable to a reader, and
    // collapsing the two is the single most repeated bug in this codebase.
    // Two pumps, same reasoning as the analogous case in
    // defence_readiness_list_test.dart: the first resolves the outer
    // myAdviseesProvider stream (mounting the advisee's own card), the
    // second lets that card's chaptersProvider start -- but its stream has
    // not emitted yet, so the card's own loading branch is what should show.
    final db = await _seed();
    // The mode is resolved up front so this test isolates the stream it is
    // actually about. Without it the dashboard-level mode gate renders its
    // own spinner first and the assertion would target the wrong one.
    await tester.pumpWidget(await _wrap(db, uid: 'a1', overrides: [
      effectiveFacultyModeProvider
          .overrideWith((ref) async => FacultyMode.adviser),
      // A chapter stream that never emits, so the card's own loading branch
      // is genuinely observable -- fake_cloud_firestore settles inside a
      // pump, which is why the previous two-pump timing no longer holds.
      chaptersProvider('mine')
          .overrideWith((ref) => StreamController<List<ThesisChapter>>().stream),
    ]));
    // The two-pump timing: the first resolves myAdviseesProvider (mounting
    // the advisee's own card), the second lets that card's chaptersProvider
    // start -- but its stream has not emitted yet, so the card's own
    // loading branch is what should show.
    await tester.pump();
    await tester.pump();

    expect(find.text('Awaiting review: still loading…'), findsOneWidget);
    expect(find.textContaining('0 chapters awaiting review'), findsNothing);
    expect(find.text('Nothing awaiting review'), findsNothing);
  });
}
