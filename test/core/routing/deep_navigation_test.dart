import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Task 9: `context.push` for the five deep routes below a destination,
/// `context.go` for the destinations themselves. Every navigation call in
/// the app used to be `context.go`, which REPLACES the route rather than
/// pushing onto it -- so there was no Navigator stack, and "back" could
/// only re-navigate to the list, reloading it from the top and losing
/// scroll position.
///
/// THE TEST THAT MATTERS asserts on the observable consequence (the scroll
/// offset survives the round trip), not on which router method fired -- a
/// "the route changed" assertion passes whether the call site pushes or
/// goes, and would not have caught the regression this task exists to fix.
Future<ProviderContainer> containerForRole(
    String role, FakeFirebaseFirestore db,
    {String uid = 'u1'}) async {
  await db.collection('users').doc(uid).set({
    'fullName': 'Test',
    'email': 't@isufst.edu.ph',
    'role': role,
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

Future<void> pumpRouted(
  WidgetTester tester,
  ProviderContainer c, {
  double width = 1000,
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: c.read(goRouterProvider)),
  ));
  await tester.pumpAndSettle();
}

Map<String, dynamic> approvedThesis({
  String leaderUid = 'u1',
  String adviserUid = 'a1',
  List<String> panelistUids = const [],
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': adviserUid,
      'panelistUids': panelistUids,
      'memberNames': <String>[],
      'workingTitle': 'A Working Title',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': 'titleApproved',
    };

void main() {
  testWidgets('back from a chapter restores the list scroll position',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(approvedThesis());
    final c = await containerForRole('student', db, uid: 'u1');
    addTearDown(c.dispose);
    // A short viewport so the five chapter rows overflow and there is a
    // real, non-zero offset to lose -- a list that already fits proves
    // nothing.
    await pumpRouted(tester, c, height: 420);

    c.read(goRouterProvider).go('/thesis/chapters?id=t1');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);

    final scrollableFinder = find
        .descendant(
          of: find.byKey(const Key('chaptersScreen')),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.drag(scrollableFinder, const Offset(0, -200));
    await tester.pumpAndSettle();
    final offsetBeforePush =
        tester.state<ScrollableState>(scrollableFinder).position.pixels;
    expect(offsetBeforePush, greaterThan(0),
        reason: 'the drag must have produced a real scroll to lose');

    // Tapping into a chapter exercises the real call site
    // (chapters_screen.dart), not a router API called directly from the
    // test -- this is what would break if that call site were ever
    // reverted from `push` back to `go`.
    await tester.tap(find.byKey(const Key('chapterRow-chapterI')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chapterDetailScreen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shellBack')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
    final offsetAfterPop =
        tester.state<ScrollableState>(scrollableFinder).position.pixels;
    expect(offsetAfterPop, offsetBeforePush,
        reason: 'a re-navigation (go) resets scroll to zero on the way '
            'back in; push must leave the list mounted underneath so its '
            'scroll position survives the round trip');
  });

  testWidgets('the shell shows a back control inside a pushed chapter',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(approvedThesis());
    final c = await containerForRole('student', db, uid: 'u1');
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    c.read(goRouterProvider).go('/thesis/chapters?id=t1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chapterRow-chapterIII')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chapterDetailScreen')), findsOneWidget);
    expect(find.byKey(const Key('shellBack')), findsOneWidget);
  });

  testWidgets(
      'a deep route opened directly by URL, with nothing beneath it, does '
      'not crash when back is tapped', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(
        approvedThesis(leaderUid: 'u1', adviserUid: 'a1', panelistUids: [
      'p1',
    ]));
    await db.collection('defenses').doc('df1').set({
      'thesisId': 't1',
      'type': 'preOral',
      'venue': 'Room 101',
      'panelUids': ['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'u1',
      'status': 'scheduled',
      'createdBy': 'c1',
    });
    final c = await containerForRole('student', db, uid: 'u1');
    addTearDown(c.dispose);
    await pumpRouted(tester, c);

    // Reached directly -- nothing was pushed beneath this location, so the
    // Navigator has nothing to pop.
    c.read(goRouterProvider).go('/defence/room/df1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRoom')), findsOneWidget);
    expect(find.byKey(const Key('shellBack')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shellBack')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
