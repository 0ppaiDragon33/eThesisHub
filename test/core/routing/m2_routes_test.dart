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
  // A student is the actor these routes exist for: they're the ones who
  // upload chapters. 't1' is titleApproved -- the status the chapters
  // screen itself requires before it will show anything but a locked
  // message. Parameterised over role/uid so the same fixture can stand in
  // as either the student leader ('u1', the default) or the thesis's own
  // adviser -- the redirect guard in app_router.dart's redirect callback
  // must let both through before the route builder ever runs.
  Future<ProviderContainer> setUpApprovedThesis(
    WidgetTester tester, {
    String role = 'student',
    String uid = 'u1',
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'u1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    final c = await containerFor(role, uid, db);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('a student reaches the chapters screen', (tester) async {
    final c = await setUpApprovedThesis(tester);

    c.read(goRouterProvider).go('/thesis/chapters?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
  });

  testWidgets('a chapter id in the path reaches the detail screen',
      (tester) async {
    final c = await setUpApprovedThesis(tester);

    c.read(goRouterProvider).go('/thesis/chapters/chapterIII?id=t1');
    await tester.pumpAndSettle();

    // The app bar names the chapter regardless of whether it has been
    // started yet -- chapter_detail_screen.dart's `_framed` puts
    // `widget.chapter.label` in the AppBar on every branch, loading, error
    // and not-started alike -- so this is a stable signal that the detail
    // route, not the chapters list, is what actually rendered.
    expect(find.widgetWithText(AppBar, 'Chapter III — Methodology'),
        findsOneWidget);
  });

  testWidgets(
      'an unknown chapter id does not open a blank screen', (tester) async {
    final c = await setUpApprovedThesis(tester);

    // ChapterId.fromString returns null for an id that is not one of the
    // five chapters, by design -- a route builder that force-unwrapped it
    // (`ChapterId.fromString(...)!`) would throw during build and Flutter
    // would show a white error screen with no way back.
    c.read(goRouterProvider).go('/thesis/chapters/chapterIX?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chapterDetailScreen')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('No such chapter'), findsOneWidget);
  });

  testWidgets('a missing id query parameter is refused, with a way back',
      (tester) async {
    // Signed in as the ADVISER, not the leader. A bare '/thesis/chapters'
    // from a STUDENT now falls back to their own thesis, because the
    // sidebar's Chapters destination is exactly that bare path and cannot
    // carry a query parameter (see bareVisitFallbackPaths in
    // app_router.dart). An adviser has no such fallback -- 'the leader's
    // own thesis' means nothing for them -- so they are the reader who can
    // still land here, and the refusal must still be somewhere they can
    // leave from.
    final c = await setUpApprovedThesis(tester, role: 'faculty', uid: 'a1');

    c.read(goRouterProvider).go('/thesis/chapters');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsNothing);
    // Exactly one app bar -- the shell's, which also carries the sidebar
    // and so the way out.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('No thesis given'), findsOneWidget);
  });

  testWidgets('the sidebar Chapters destination resolves to the leader\'s '
      'own thesis', (tester) async {
    // The destination is a bare '/thesis/chapters': a sidebar entry is one
    // fixed route and cannot carry the thesis id only the signed-in leader
    // supplies. Without the fallback, tapping Chapters would land every
    // student on "No thesis given" -- a control that does nothing, which
    // is precisely what the destination list is curated to avoid.
    final c = await setUpApprovedThesis(tester);

    c.read(goRouterProvider).go('/thesis/chapters');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
    expect(find.text('No thesis given'), findsNothing);
  });

  // The scenario the studentOnly-guard exemption in app_router.dart's
  // redirect callback exists for. Every test above signs in as the student
  // leader, so none of them would notice if that exemption were ever
  // dropped -- the redirect would silently bounce the adviser back to
  // '/faculty' before ChaptersScreen ever built, and this suite would still
  // report green. Signed in as 'a1', which the fixture's thesis 't1' already
  // names as `adviserUid` -- the real actor this route is for, not an
  // arbitrary faculty account with no relationship to the thesis.
  testWidgets('a faculty adviser reaches the chapters screen', (tester) async {
    final c = await setUpApprovedThesis(tester, role: 'faculty', uid: 'a1');

    c.read(goRouterProvider).go('/thesis/chapters?id=t1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
  });
}
