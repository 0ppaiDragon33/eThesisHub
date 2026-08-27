import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

Future<ProviderContainer> containerFor(String role, String uid,
    {FakeFirebaseFirestore? db, List<Override> additionalOverrides = const []}) async {
  final firestore = db ?? FakeFirebaseFirestore();
  await firestore.collection('users').doc(uid).set({
    'fullName': 'Test', 'email': 't@isufst.edu.ph', 'role': role,
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
          uid: uid, email: 't@isufst.edu.ph', isEmailVerified: true),
    )),
    ...additionalOverrides,
  ]);
}

/// Pumps the app wide enough (1000px) for the shell to draw its rail.
///
/// Every "reaches X by tapping" case below taps a sidebar destination or a
/// link on the page one destination across. Those destinations used to be
/// a dashboard's own bar; they belong to the one app shell now, which
/// hides them behind a hamburger below 900px -- so on the default 800px
/// test surface the drawer would be shut and every such tap would find
/// nothing.
Future<void> pumpApp(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a student can reach the create-thesis screen', (tester) async {
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/thesis/create');
    await tester.pumpAndSettle();
    expect(find.text('Create thesis group'), findsOneWidget);
  });

  testWidgets(
      'a student reaches create-thesis by tapping, not just by knowing '
      'the URL', (tester) async {
    // The only in-app door to '/thesis/create' used to be a button on the
    // student dashboard, which this milestone deletes. It moved onto the
    // 'My thesis' destination that replaced that dashboard's Thesis tab,
    // so the tap is one destination across rather than on first paint --
    // and this test still fails if that door disappears entirely, which is
    // the whole point of it existing.
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('My thesis')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToCreateThesis')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToCreateThesis')));
    await tester.pumpAndSettle();

    expect(find.text('Create thesis group'), findsWidgets);
  });

  testWidgets('a student reaches their thesis status screen from the dashboard',
      (tester) async {
    // Needs a thesis to exist: with none, the dashboard shows the
    // create-your-group empty state instead, which is the correct
    // behaviour and has its own test above.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').add({
      'leaderUid': 'u1', 'status': 'draft', 'panelistUids': [],
      'adviserUid': null, 'memberNames': [], 'workingTitle': 'A thesis',
      'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
      'academicYear': '2026-2027',
    });
    final c = await containerFor('student', 'u1', db: db);
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    // The 'goToThesis' button lived on the student dashboard, which this
    // milestone deletes; the thesis status screen is a sidebar destination
    // of its own now. The property is unchanged -- a student reaches their
    // thesis by TAPPING, not only by typing the URL -- and the tap is on
    // the destination rather than on a button that pointed at it.
    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('My thesis')));
    await tester.pumpAndSettle();

    // The destination screen's own Key, never a heading the origin shares
    // -- that is what made four M1a navigation tests pass without
    // navigating.
    expect(find.byKey(const Key('thesisStatusScreen')), findsOneWidget);
  });

  testWidgets('a faculty member can reach the nomination inbox',
      (tester) async {
    final c = await containerFor('faculty', 'u2');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/nominations');
    await tester.pumpAndSettle();
    expect(find.text('Nomination inbox'), findsOneWidget);
  });

  testWidgets(
      'a faculty member reaches the nomination inbox from the dashboard link',
      (tester) async {
    final c = await containerFor('faculty', 'u2');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    // The Conforme inbox is its own destination now, in both faculty
    // modes -- a nomination belongs to neither role, it is how you acquire
    // one. The 'goToInbox' button lived on the deleted faculty dashboard's
    // Nominations tab and pointed at this same route; the destination goes
    // there directly.
    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('Nominations')));
    await tester.pumpAndSettle();

    // The destination screen's own Key, never a heading the origin shares.
    expect(find.byKey(const Key('nominationInboxScreen')), findsOneWidget);
  });

  testWidgets('a coordinator reaches the review queue from the dashboard link',
      (tester) async {
    final c = await containerFor('coordinator', 'u5');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    // Overview lands first for the coordinator; the review-queue link with
    // its own key sits on the Recommendations destination, which is a
    // sidebar entry in the shell now rather than a dashboard tab.
    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('Recommendations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToReview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToReview')));
    await tester.pumpAndSettle();

    // 'Nomination recommendations' is both the button's label and the
    // destination's AppBar title, so it would match whether or not
    // navigation happened. Assert on the destination screen's own Key
    // instead, and that the dashboard button is actually gone.
    expect(find.byKey(const Key('reviewQueueScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToReview')), findsNothing);
  });

  testWidgets('a coordinator reaches the faculty invites screen', (tester) async {
    // This caught a real defect: '/faculty' was registered twice — the
    // faculty dashboard and then this screen — and go_router takes the
    // first match, so the invites screen was unreachable and the button
    // landed the coordinator on the faculty dashboard instead. The screen's
    // own widget tests pump it directly, bypassing the router, so only a
    // navigation test can see this.
    final c = await containerFor('coordinator', 'u5');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    // Overview lands first; the link with its own key sits on the
    // Recommendations destination.
    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('Recommendations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToFaculty')), findsOneWidget);
    // PageShell scrolls but tester.tap() does not scroll for you.
    await tester.ensureVisible(find.byKey(const Key('goToFaculty')));
    await tester.tap(find.byKey(const Key('goToFaculty')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('facultyInvitesScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToFaculty')), findsNothing);
  });

  testWidgets(
      'the coordinator Faculty destination reaches /invites after the '
      'Overview shift', (tester) async {
    // Prepending Overview shifted every other coordinator destination's
    // index by one -- Faculty moved from index 4 to index 5. The dashboard
    // used to jump on a hard-coded `if (i == 4)`, which would have silently
    // routed this exact tap (now index 5) to whatever destination 4
    // (Readiness) renders instead, with no error. This is the regression
    // test for that literal, exercised through the real router the way the
    // bug actually shipped.
    final c = await containerFor('coordinator', 'u5');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('Faculty')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('facultyInvitesScreen')), findsOneWidget);
    expect(find.byKey(const Key('coordinatorOverview')), findsNothing);
    expect(find.byKey(const Key('readinessScreen')), findsNothing);
  });

  testWidgets('a dean reaches the review (approval) queue from the dashboard link',
      (tester) async {
    final c = await containerFor('dean', 'u4');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    // Overview lands first for the dean; the approval-queue link with its
    // own key sits on the Approvals destination, which is a sidebar entry
    // in the shell now rather than a dashboard tab.
    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('Approvals')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToReview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToReview')));
    await tester.pumpAndSettle();

    // 'Nomination approvals' is both the button's label and the
    // destination's AppBar title, so it would match whether or not
    // navigation happened. Assert on the destination screen's own Key
    // instead, and that the dashboard button is actually gone.
    expect(find.byKey(const Key('reviewQueueScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToReview')), findsNothing);
  });

  testWidgets('a student cannot reach the review queue', (tester) async {
    final c = await containerFor('student', 'u3');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/review');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reviewQueueScreen')), findsNothing);
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
  });

  testWidgets('a student cannot reach the nomination inbox', (tester) async {
    final c = await containerFor('student', 'u3');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/nominations');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nominationInboxScreen')), findsNothing);
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
  });

  testWidgets('a faculty member cannot reach the create-thesis screen',
      (tester) async {
    final c = await containerFor('faculty', 'u2');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/thesis/create');
    await tester.pumpAndSettle();
    expect(find.text('Create thesis group'), findsNothing);
    expect(find.byKey(const Key('facultyOverview')), findsOneWidget);
  });

  testWidgets(
      'a bare visit to /thesis/nominate falls back to the leader\'s own '
      'thesis instead of crashing', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerFor('student', 'u1', db: db);
    addTearDown(c.dispose);
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'u1', 'status': 'draft', 'panelistUids': <String>[],
      'adviserUid': null, 'memberNames': <String>[],
      'workingTitle': 'eThesisHub', 'college': 'CICT', 'program': 'BSIT',
      'semester': 'First', 'academicYear': '2026-2027',
    });

    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/thesis/nominate');
    await tester.pumpAndSettle();

    // No crash, and it lands on the nominate screen for the leader's own
    // thesis rather than an unhandled null-check error. The heading is the
    // shell's app bar title for this route now (see shellTitleFor), the
    // screen having given up its own AppBar to the shell.
    expect(find.text('Nominate adviser and panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a bare visit to /thesis/nominate does not misroute to create-thesis '
      'while myThesisProvider is still loading (the load race)',
      (tester) async {
    // Controls exactly when myThesisProvider settles, so the "still
    // loading" window is reproduced deterministically instead of racing
    // real Firestore timing. Before the fix, the redirect read
    // `.valueOrNull` on this still-loading AsyncValue, treated it the same
    // as a settled "no thesis", and sent a leader who genuinely has one to
    // /thesis/create. On Web that is exactly what a page reload of
    // /thesis/nominate hits: the provider has not delivered its first
    // snapshot yet.
    final controller = StreamController<Thesis?>();
    addTearDown(controller.close);

    final c = await containerFor('student', 'u1', additionalOverrides: [
      myThesisProvider.overrideWith((ref) => controller.stream),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    // Also not pumpAndSettle, one step earlier and for the same reason: the
    // student dashboard itself now renders a spinner while myThesisProvider
    // is unsettled, and this test holds it unsettled on purpose.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    c.read(goRouterProvider).go('/thesis/nominate');
    // Not pumpAndSettle: the loading branch renders a CircularProgress
    // Indicator, whose implicit animation would keep scheduling frames
    // forever since myThesisProvider deliberately has not emitted yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // The fix under test: while unsettled, the redirect must not have
    // already committed to /thesis/create.
    expect(find.text('Create thesis group'), findsNothing);
    expect(find.byKey(const Key('nominateBareVisitLoading')), findsOneWidget);

    // Now the leader's thesis actually arrives.
    controller.add(Thesis(
      id: 't1',
      leaderUid: 'u1',
      memberNames: [],
      workingTitle: 'eThesisHub',
      college: 'CICT',
      program: 'BSIT',
      semester: 'First',
      academicYear: '2026-2027',
      status: ThesisStatus.draft,
      panelistUids: [],
      createdAt: DateTime(2026, 1, 1),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Nominate adviser and panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
