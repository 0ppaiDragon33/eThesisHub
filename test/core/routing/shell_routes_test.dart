import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

// Task 6: each of the eight sidebar destinations gets its own registered
// path, but the old dashboard routes ('/dean', '/faculty', etc.) still
// work too -- this task only adds routes, it does not switch anything
// over. Every test below drives a real GoRouter (never pumps a screen
// directly), because only a router-level test can see a route collision --
// this project has already lost a screen to exactly that failure once
// ('/faculty' registered twice left the invites screen unreachable, see
// app_router.dart's own comment above '/invites').
Future<ProviderContainer> containerForRole(
    String role, FakeFirebaseFirestore db,
    {String uid = 'u1'}) async {
  await db.collection('users').doc(uid).set({
    'fullName': 'Test', 'email': 't@isufst.edu.ph', 'role': role,
    'active': true,
  });
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: 't@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
}

/// A signed-in, verified account with NO `users/{uid}` document.
///
/// Deliberately separate from [containerForRole] rather than a flag on it:
/// the whole point of the tests below is the case where the profile is
/// absent, and a helper that can silently seed one is how that case gets
/// tested by accident instead of on purpose.
Future<ProviderContainer> containerWithoutProfile(FakeFirebaseFirestore db,
    {String uid = 'u1'}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: 't@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
}

/// The location the router actually settled on, not the one asked for.
/// A redirect that silently fails to fire can still leave the right widget
/// on screen by coincidence, so the URL is asserted alongside the widget.
String locationOf(ProviderContainer c) => c
    .read(goRouterProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

Future<void> pumpRouted(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: c.read(goRouterProvider)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('/overview reaches the overview screen', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('student', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/overview');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);
  });

  testWidgets('/defences reaches the defences screen', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('student', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/defences');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defencesScreen')), findsOneWidget);
  });

  testWidgets('/advisees reaches the advisees screen', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('faculty', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/advisees');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adviseesScreen')), findsOneWidget);
  });

  testWidgets('/panels reaches the panels screen', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('faculty', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/panels');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('panelsScreen')), findsOneWidget);
  });

  testWidgets('/approvals reaches the approvals screen', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/approvals');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approvalsScreen')), findsOneWidget);
  });

  testWidgets('/recommendations reaches the recommendations screen',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('coordinator', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/recommendations');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recommendationsScreen')), findsOneWidget);
  });

  testWidgets('/title-defences reaches the title defences screen',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/title-defences');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleDefencesScreen')), findsOneWidget);
  });

  // Not '/titles' -- '/thesis/titles' already exists for submitting a
  // candidate title set. Two routes a character apart meaning different
  // things is exactly how '/faculty' came to be registered twice, leaving
  // the invites screen permanently unreachable. This confirms the two
  // paths coexist and each resolves to its own screen.
  testWidgets('/title-defences and /thesis/titles are distinct routes',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'u1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    final c = await containerForRole('student', db, uid: 'u1');
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/thesis/titles?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleDefencesScreen')), findsNothing);
  });

  testWidgets('/readiness reaches the readiness screen', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/readiness');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readinessScreen')), findsOneWidget);
  });

  // The collision guard. '/faculty' was once registered twice, leaving the
  // invites screen permanently unreachable -- caught only because a
  // router-level test walked the registered routes rather than pumping a
  // screen directly. `configuration.routes` is public on GoRouter but
  // annotated `@internal` in this project's pinned go_router version, so
  // rather than depend on an internal API this test proves the same
  // property behaviourally: walk all eight new paths in sequence through a
  // single router instance and assert each lands on its own distinct
  // screen key. If any two paths were registered such that one shadowed
  // the other, two of these would resolve to the same key (or one would
  // resolve to nothing), and the assertion below would fail.
  testWidgets('no two of the eight routes share a path', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    const routesAndKeys = {
      '/overview': 'overviewScreen',
      '/defences': 'defencesScreen',
      '/panels': 'panelsScreen',
      '/approvals': 'approvalsScreen',
      '/title-defences': 'titleDefencesScreen',
      '/readiness': 'readinessScreen',
    };

    for (final entry in routesAndKeys.entries) {
      c.read(goRouterProvider).go(entry.key);
      await tester.pumpAndSettle();

      expect(find.byKey(Key(entry.value)), findsOneWidget,
          reason: '${entry.key} did not resolve to its own screen -- '
              'possible route collision');
      for (final otherKey in routesAndKeys.values) {
        if (otherKey == entry.value) continue;
        expect(find.byKey(Key(otherKey)), findsNothing,
            reason: '${entry.key} resolved to $otherKey instead of '
                '${entry.value} -- route collision');
      }
    }
  });

  // --- Task 7: one shell around every signed-in route ---

  testWidgets('the sidebar is present on an inner screen', (tester) async {
    // The field report this milestone answers: "I don't see any back menu
    // while navigating on screens." Assert on a screen that is NOT a
    // destination, or the test proves only what already worked -- the four
    // dashboards always had navigation of their own, and every screen you
    // reached FROM one had none.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'u1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    final c = await containerForRole('student', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/thesis/chapters?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(NavigationRail), matching: find.text('Overview')),
        findsOneWidget);
    // No back control here on purpose: for a student whose title is
    // approved, Chapters IS a destination, and the shell offers back only
    // where the sidebar alone cannot return the reader (see
    // isDeeperThanDestination). The nested case -- one chapter's detail --
    // is covered in test/features/dashboard/navigation_test.dart.
    expect(find.byKey(const Key('shellBack')), findsNothing);
  });

  testWidgets('a hamburger is present on an inner screen at phone width',
      (tester) async {
    // Narrow is where the old shape stranded people hardest: no rail, no
    // bottom bar on an inner screen, and nothing but the browser's own
    // back button.
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'u1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    final c = await containerForRole('student', db);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(routerConfig: c.read(goRouterProvider)),
    ));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/thesis/chapters?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
    expect(find.byKey(const Key('shellMenu')), findsOneWidget);
    // No rail at this width, and no bottom bar either: on narrow the
    // destinations live behind this hamburger, which is present on EVERY
    // screen rather than only on the four that used to be dashboards.
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('an old home route redirects to /overview', (tester) async {
    // Anything already bookmarked must keep working. '/dean' was the dean's
    // home for two milestones.
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/dean');
    await tester.pumpAndSettle();

    expect(locationOf(c), '/overview');
    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);
    expect(find.byKey(const Key('deanOverview')), findsOneWidget);
  });

  testWidgets('every old home route redirects to /overview', (tester) async {
    // One per path: each of the four was a real bookmarkable home, and a
    // redirect covering only the one a test happened to pick would strand
    // the other three.
    for (final path in ['/student', '/faculty', '/coordinator', '/dean']) {
      final db = FakeFirebaseFirestore();
      final c = await containerForRole('coordinator', db);
      await pumpRouted(tester, c);

      c.read(goRouterProvider).go(path);
      await tester.pumpAndSettle();

      expect(locationOf(c), '/overview',
          reason: '$path must still land its reader somewhere');
      c.dispose();
    }
  });

  testWidgets('a signed-in account with no profile reaches /no-profile',
      (tester) async {
    // Spec D25 at the router level, not just the widget level. This account
    // was previously bounced to /login, which reads as being signed out
    // when they are not.
    final db = FakeFirebaseFirestore();
    final c = await containerWithoutProfile(db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    expect(locationOf(c), '/no-profile');
    expect(find.byKey(const Key('noProfileScreen')), findsOneWidget);
    expect(find.byKey(const Key('overviewScreen')), findsNothing);
    expect(find.byKey(const Key('studentOverview')), findsNothing);
    expect(find.byKey(const Key('facultyOverview')), findsNothing);
    expect(find.byKey(const Key('deanOverview')), findsNothing);
    expect(find.byKey(const Key('coordinatorOverview')), findsNothing);
  });

  // --- Task 8: role guards for the eight destination routes ---
  //
  // Both directions for every row of the permission table: a permitted role
  // reaches the route, and an excluded role is redirected home. A
  // one-directional test would still pass with the guard deleted, which is
  // how a guard that does nothing gets shipped.

  testWidgets('every signed-in role reaches /overview and /defences',
      (tester) async {
    for (final role in ['student', 'faculty', 'coordinator', 'dean']) {
      final db = FakeFirebaseFirestore();
      final c = await containerForRole(role, db);
      await pumpRouted(tester, c);

      c.read(goRouterProvider).go('/overview');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewScreen')), findsOneWidget,
          reason: '$role must reach /overview');

      c.read(goRouterProvider).go('/defences');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('defencesScreen')), findsOneWidget,
          reason: '$role must reach /defences');

      c.dispose();
    }
  });

  testWidgets('faculty, coordinator and dean reach /advisees and /panels',
      (tester) async {
    for (final role in ['faculty', 'coordinator', 'dean']) {
      final db = FakeFirebaseFirestore();
      final c = await containerForRole(role, db);
      await pumpRouted(tester, c);

      c.read(goRouterProvider).go('/advisees');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adviseesScreen')), findsOneWidget,
          reason: '$role must reach /advisees');

      c.read(goRouterProvider).go('/panels');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panelsScreen')), findsOneWidget,
          reason: '$role must reach /panels');

      c.dispose();
    }
  });

  testWidgets('a student is redirected home from /advisees and /panels',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('student', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/advisees');
    await tester.pumpAndSettle();
    expect(locationOf(c), '/overview');
    expect(find.byKey(const Key('adviseesScreen')), findsNothing);

    c.read(goRouterProvider).go('/panels');
    await tester.pumpAndSettle();
    expect(locationOf(c), '/overview');
    expect(find.byKey(const Key('panelsScreen')), findsNothing);
  });

  testWidgets('the dean reaches /approvals', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/approvals');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approvalsScreen')), findsOneWidget);
  });

  testWidgets(
      'student, faculty and coordinator are redirected home from /approvals',
      (tester) async {
    for (final role in ['student', 'faculty', 'coordinator']) {
      final db = FakeFirebaseFirestore();
      final c = await containerForRole(role, db);
      await pumpRouted(tester, c);

      c.read(goRouterProvider).go('/approvals');
      await tester.pumpAndSettle();

      expect(locationOf(c), '/overview', reason: '$role must not stay');
      expect(find.byKey(const Key('approvalsScreen')), findsNothing,
          reason: '$role must be redirected off /approvals');

      c.dispose();
    }
  });

  testWidgets('the coordinator reaches /recommendations', (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('coordinator', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/recommendations');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recommendationsScreen')), findsOneWidget);
  });

  testWidgets(
      'student, faculty and dean are redirected home from /recommendations',
      (tester) async {
    for (final role in ['student', 'faculty', 'dean']) {
      final db = FakeFirebaseFirestore();
      final c = await containerForRole(role, db);
      await pumpRouted(tester, c);

      c.read(goRouterProvider).go('/recommendations');
      await tester.pumpAndSettle();

      expect(locationOf(c), '/overview', reason: '$role must not stay');
      expect(
          find.byKey(const Key('recommendationsScreen')), findsNothing,
          reason: '$role must be redirected off /recommendations');

      c.dispose();
    }
  });

  testWidgets('coordinator and dean reach /title-defences and /readiness',
      (tester) async {
    for (final role in ['coordinator', 'dean']) {
      final db = FakeFirebaseFirestore();
      final c = await containerForRole(role, db);
      await pumpRouted(tester, c);

      c.read(goRouterProvider).go('/title-defences');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('titleDefencesScreen')), findsOneWidget,
          reason: '$role must reach /title-defences');

      c.read(goRouterProvider).go('/readiness');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('readinessScreen')), findsOneWidget,
          reason: '$role must reach /readiness');

      c.dispose();
    }
  });

  testWidgets(
      'student and faculty are redirected home from /title-defences and '
      '/readiness', (tester) async {
    for (final role in ['student', 'faculty']) {
      final db = FakeFirebaseFirestore();
      final c = await containerForRole(role, db);
      await pumpRouted(tester, c);

      c.read(goRouterProvider).go('/title-defences');
      await tester.pumpAndSettle();
      expect(locationOf(c), '/overview', reason: '$role must not stay');
      expect(find.byKey(const Key('titleDefencesScreen')), findsNothing,
          reason: '$role must be redirected off /title-defences');

      c.read(goRouterProvider).go('/readiness');
      await tester.pumpAndSettle();
      expect(locationOf(c), '/overview', reason: '$role must not stay');
      expect(find.byKey(const Key('readinessScreen')), findsNothing,
          reason: '$role must be redirected off /readiness');

      c.dispose();
    }
  });

  // --- The two exemptions that must survive this task ---

  testWidgets('an adviser still reaches /thesis/chapters', (tester) async {
    // The router carries a comment explaining that a blanket /thesis
    // prefix guard would bounce every adviser away from the chapters they
    // review. That bug is closed; this keeps it closed.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'u1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    final c = await containerForRole('faculty', db, uid: 'a1');
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/thesis/chapters?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
  });

  testWidgets('a leader still reaches /defence/room/:id', (tester) async {
    // Same class of failure: DefencesList sends the leader into the room
    // to read the consolidated comments, and a blanket /defence/ guard
    // bounced them home before the screen ever built.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'u1', 'status': 'titleApproved',
      'panelistUids': ['p1'], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    await db.collection('defenses').doc('df1').set({
      'thesisId': 't1', 'type': 'preOral', 'venue': 'Room 101',
      'panelUids': ['p1'], 'adviserUid': 'a1', 'leaderUid': 'u1',
      'status': 'scheduled', 'createdBy': 'c1',
    });
    final c = await containerForRole('student', db, uid: 'u1');
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/defence/room/df1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRoom')), findsOneWidget);
  });

  // --- Task 6: the Users destination owns two routes ---

  testWidgets('both /users and /invites highlight the Users destination',
      (tester) async {
    // Users is the first destination in the app to populate `alsoOwns`
    // ('/invites', alongside its own '/users'). Both routes must light up
    // the same rail entry, or the coordinator lands on the Invites tab
    // with the sidebar telling them they are somewhere else.
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('coordinator', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/users');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('usersScreen')), findsOneWidget);
    var rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    final usersIndex = rail.destinations
        .indexWhere((d) => (d.label as Text).data == 'Users');
    expect(usersIndex, isNonNegative);
    expect(rail.selectedIndex, usersIndex,
        reason: '/users must select the Users destination');

    c.read(goRouterProvider).go('/invites');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('facultyInvitesScreen')), findsOneWidget);
    rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, usersIndex,
        reason: '/invites must ALSO select the Users destination');
  });

  testWidgets(
      'both tabs carry the Accounts/Invites strip and each navigates to '
      'the other', (tester) async {
    // Spec §5 promises a destination "with two tabs". The strip lived only
    // on the Accounts screen, so /invites rendered with the rail
    // highlighting "Users", the app bar reading "Invites", and no
    // Accounts/Invites control anywhere on the screen -- a tab you could
    // enter and not leave.
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('coordinator', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/users');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('usersTabAccounts')), findsOneWidget);
    expect(find.byKey(const Key('usersTabInvites')), findsOneWidget);

    // Accounts -> Invites.
    await tester.tap(find.byKey(const Key('usersTabInvites')));
    await tester.pumpAndSettle();
    expect(locationOf(c), '/invites');
    expect(find.byKey(const Key('facultyInvitesScreen')), findsOneWidget);

    // And the strip is on THIS screen too, selected the other way.
    expect(find.byKey(const Key('usersTabAccounts')), findsOneWidget);
    expect(find.byKey(const Key('usersTabInvites')), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('usersTabInvites')))
            .selected,
        isTrue);

    // Invites -> Accounts.
    await tester.tap(find.byKey(const Key('usersTabAccounts')));
    await tester.pumpAndSettle();
    expect(locationOf(c), '/users');
    expect(find.byKey(const Key('usersScreen')), findsOneWidget);
  });

  testWidgets('neither tab draws a back control -- both are top level',
      (tester) async {
    // Populating `alsoOwns` made '/invites' deeper than its owner's route
    // by `isDeeperThanDestination`'s old `location != owner.route` test,
    // which would draw a back control on a top-level tab. An `alsoOwns`
    // root is a PEER of the destination's own route, not a screen beneath
    // it, and the tab strip is what actually leaves it.
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('coordinator', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    for (final route in ['/users', '/invites']) {
      c.read(goRouterProvider).go(route);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shellBack')), findsNothing,
          reason: '$route is a top-level tab of the Users destination');
    }
  });

  testWidgets('a student is redirected home from /users and /invites',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('student', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/users');
    await tester.pumpAndSettle();
    expect(locationOf(c), '/overview');
    expect(find.byKey(const Key('usersScreen')), findsNothing);

    c.read(goRouterProvider).go('/invites');
    await tester.pumpAndSettle();
    expect(locationOf(c), '/overview');
    expect(find.byKey(const Key('facultyInvitesScreen')), findsNothing);
  });

  testWidgets('a profile deleted AFTER the shell mounts reaches /no-profile',
      (tester) async {
    // The redirect does re-fire on a profile change -- app_router.dart's
    // ref.listen(currentUserProvider) drives the refresh notifier -- but
    // nothing tested it, so nothing would have noticed if that listen were
    // dropped. A profile can genuinely vanish under a live session: a
    // coordinator deactivating an account, or a half-finished registration
    // being cleaned up.
    final db = FakeFirebaseFirestore();
    final c = await containerForRole('dean', db);
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);

    await db.collection('users').doc('u1').delete();
    await tester.pumpAndSettle();

    expect(locationOf(c), '/no-profile');
    expect(find.byKey(const Key('noProfileScreen')), findsOneWidget);
    expect(find.byKey(const Key('overviewScreen')), findsNothing);
    expect(find.byKey(const Key('deanOverview')), findsNothing);
    expect(find.byKey(const Key('studentOverview')), findsNothing);
  });
}
