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

Future<ProviderContainer> containerFor(String role, String uid,
    {FakeFirebaseFirestore? db}) async {
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
  ]);
}

void main() {
  testWidgets('a student can reach the create-thesis screen', (tester) async {
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/thesis/create');
    await tester.pumpAndSettle();
    expect(find.text('Create thesis group'), findsOneWidget);
  });

  testWidgets(
      'a student reaches create-thesis from the dashboard by tapping, not '
      'just by knowing the URL', (tester) async {
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToCreateThesis')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToCreateThesis')));
    await tester.pumpAndSettle();

    expect(find.text('Create thesis group'), findsOneWidget);
  });

  testWidgets('a student reaches their thesis status screen from the dashboard',
      (tester) async {
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToThesis')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToThesis')));
    await tester.pumpAndSettle();

    expect(find.text('My thesis'), findsOneWidget);
  });

  testWidgets('a faculty member can reach the nomination inbox',
      (tester) async {
    final c = await containerFor('faculty', 'u2');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/nominations');
    await tester.pumpAndSettle();
    expect(find.text('Nomination inbox'), findsOneWidget);
  });

  testWidgets(
      'a faculty member reaches the nomination inbox from the dashboard link',
      (tester) async {
    final c = await containerFor('faculty', 'u2');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToInbox')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToInbox')));
    await tester.pumpAndSettle();

    expect(find.text('Nomination inbox'), findsOneWidget);
  });

  testWidgets('a coordinator reaches the review queue from the dashboard link',
      (tester) async {
    final c = await containerFor('coordinator', 'u5');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToReview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToReview')));
    await tester.pumpAndSettle();

    expect(find.text('Nomination recommendations'), findsOneWidget);
  });

  testWidgets('a dean reaches the review (approval) queue from the dashboard link',
      (tester) async {
    final c = await containerFor('dean', 'u4');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToReview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToReview')));
    await tester.pumpAndSettle();

    expect(find.text('Nomination approvals'), findsOneWidget);
  });

  testWidgets('a student cannot reach the review queue', (tester) async {
    final c = await containerFor('student', 'u3');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/review');
    await tester.pumpAndSettle();
    expect(find.text('Nomination recommendations'), findsNothing);
    expect(find.text('My Thesis'), findsOneWidget);
  });

  testWidgets('a student cannot reach the nomination inbox', (tester) async {
    final c = await containerFor('student', 'u3');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/nominations');
    await tester.pumpAndSettle();
    expect(find.text('Nomination inbox'), findsNothing);
    expect(find.text('My Thesis'), findsOneWidget);
  });

  testWidgets('a faculty member cannot reach the create-thesis screen',
      (tester) async {
    final c = await containerFor('faculty', 'u2');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/thesis/create');
    await tester.pumpAndSettle();
    expect(find.text('Create thesis group'), findsNothing);
    expect(find.text('My Advisees'), findsOneWidget);
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

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/thesis/nominate');
    await tester.pumpAndSettle();

    // No crash, and it lands on the nominate screen for the leader's own
    // thesis rather than an unhandled null-check error.
    expect(find.text('Nominate adviser and panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
