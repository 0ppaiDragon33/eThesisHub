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

    // 'My thesis' is both the button's label and the destination's AppBar
    // title, so it would match whether or not navigation happened. Assert
    // on the destination screen's own Key instead, and that the dashboard
    // button is actually gone.
    expect(find.byKey(const Key('thesisStatusScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToThesis')), findsNothing);
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

    // 'Nomination inbox' is both the button's label and the destination's
    // AppBar title, so it would match whether or not navigation happened.
    // Assert on the destination screen's own Key instead, and that the
    // dashboard button is actually gone.
    expect(find.byKey(const Key('nominationInboxScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToInbox')), findsNothing);
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

    // 'Nomination recommendations' is both the button's label and the
    // destination's AppBar title, so it would match whether or not
    // navigation happened. Assert on the destination screen's own Key
    // instead, and that the dashboard button is actually gone.
    expect(find.byKey(const Key('reviewQueueScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToReview')), findsNothing);
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
    await tester.pumpAndSettle();

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
