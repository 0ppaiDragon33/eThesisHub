import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderContainer> containerFor(
    String role, String uid, FakeFirebaseFirestore db) async {
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

void main() {
  // A fixture with one thesis ('t1', titleApproved so both the schedule
  // screen and the title defence route have something real to load) and one
  // defence ('df1', scheduled, snapshotting the same panel/adviser/leader
  // uids as the thesis) already scheduled on it. Parameterised over
  // role/uid so the same fixture can stand in as whichever actor a given
  // test needs -- the coordinator scheduling, the panel or adviser opening
  // the room, or a title-defence judge -- without rebuilding Firestore state
  // per test.
  Future<ProviderContainer> setUpFixture(
    WidgetTester tester, {
    required String role,
    required String uid,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    final c = await containerFor(role, uid, db);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('the coordinator reaches the schedule screen', (tester) async {
    final c = await setUpFixture(tester, role: 'coordinator', uid: 'c1');

    c.read(goRouterProvider).go('/defence/schedule?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheduleDefenceScreen')), findsOneWidget);
  });

  testWidgets('a panelist reaches the defence room', (tester) async {
    final c = await setUpFixture(tester, role: 'faculty', uid: 'p1');

    c.read(goRouterProvider).go('/defence/room/df1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRoom')), findsOneWidget);
    // The app bar belongs to the shell now and is titled for the ROUTE, so
    // the defence type moved to the page's own heading -- which is still
    // the thing that only renders once the defence document (not just the
    // loading state, which shares the same key) has actually resolved.
    expect(find.widgetWithText(AppBar, 'Defence room'), findsOneWidget);
    expect(find.text('Pre-oral defence'), findsOneWidget);
  });

  testWidgets('the consolidated view is reachable', (tester) async {
    // The adviser: they are the one actor who both sits in the room live
    // and later releases the consolidation, so they are guaranteed a
    // rendered page regardless of release state.
    final c = await setUpFixture(tester, role: 'faculty', uid: 'a1');

    c.read(goRouterProvider).go('/defence/room/df1/consolidated');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('consolidated')), findsOneWidget);
    // Same as the room above: the shell's app bar names the route, and the
    // defence type -- which only appears once the document resolves -- is
    // the page's own heading.
    expect(find.widgetWithText(AppBar, 'Consolidated comments'),
        findsOneWidget);
    expect(find.text('Pre-oral defence'), findsOneWidget);
  });

  // The collision guard. '/defence/schedule' and '/defence/:thesisId' share
  // the same segment count (two), so a naive reordering would let
  // ':thesisId' swallow 'schedule' as if it were a literal thesis id -- the
  // exact class of failure that made '/faculty' shadow the invites screen
  // for an entire milestone, caught that time only because a test drove the
  // router instead of pumping a screen directly.
  testWidgets("M1b's title defence still resolves", (tester) async {
    final c = await setUpFixture(tester, role: 'coordinator', uid: 'c1');

    c.read(goRouterProvider).go('/defence/t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleDefenceScreen')), findsOneWidget);
    expect(find.byKey(const Key('scheduleDefenceScreen')), findsNothing);
    expect(find.byKey(const Key('defenceRoom')), findsNothing);
  });

  testWidgets('an unknown defence id shows a not-found state with a way back',
      (tester) async {
    final c = await setUpFixture(tester, role: 'faculty', uid: 'p1');

    c.read(goRouterProvider).go('/defence/room/does-not-exist');
    await tester.pumpAndSettle();

    // DefenceRoomScreen's own "not found" branch renders under the same
    // key as its loaded state (see `_framed` in defence_room_screen.dart),
    // so the real assertion is the shell's single AppBar plus the
    // not-found copy, not the key's absence.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Defence not found'), findsOneWidget);
  });

  // The guard this task's brief warns about by name: the studentOnly
  // redirect matches '/defence/' by PREFIX, and without the
  // '/defence/room/' exemption in app_router.dart's redirect callback, this
  // would silently bounce the leader back to '/student' before
  // DefenceRoomScreen ever built -- exactly the class of bug that bounced
  // advisers off '/thesis/chapters' in M2. DefencesList (mounted on the
  // student dashboard itself, per its own doc comment) is what actually
  // sends a student down this path via its "Open" button.
  testWidgets('the student leader reaches the defence room, unlike the '
      'title defence route', (tester) async {
    final c = await setUpFixture(tester, role: 'student', uid: 'u1');

    c.read(goRouterProvider).go('/defence/room/df1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRoom')), findsOneWidget);

    // '/defence/schedule' and the title defence route are NOT exempt --
    // only '/defence/room/...' is. A student typing either by hand still
    // bounces home, same as before this task.
    c.read(goRouterProvider).go('/defence/schedule?id=t1');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheduleDefenceScreen')), findsNothing);
  });

  // FIX 6: the sibling test above only proves '/defence/room/df1' itself
  // survives the studentOnly redirect. After FIX 4, the consolidated route
  // is the student leader's PRIMARY destination -- DefencesList's Open
  // button now sends them straight there -- so it needs its own guard
  // rather than inheriting the room route's prefix exemption by assumption:
  // `isDefenceRoomRoute` in app_router.dart uses `startsWith('/defence/room/')`,
  // which happens to also cover this longer path, but nothing proved that
  // until now.
  testWidgets(
      'the student leader also reaches the consolidated route directly',
      (tester) async {
    final c = await setUpFixture(tester, role: 'student', uid: 'u1');

    c.read(goRouterProvider).go('/defence/room/df1/consolidated');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('consolidated')), findsOneWidget);
  });
}
