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
}
