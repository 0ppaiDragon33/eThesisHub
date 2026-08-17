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
  testWidgets('a student reaches the submit-titles screen from their thesis',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('theses').add({
      'leaderUid': 'u1', 'status': 'nominationApproved',
      'panelistUids': <String>[], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    final c = await containerFor('student', 'u1', db);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/thesis');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToSubmitTitles')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToSubmitTitles')));
    await tester.pumpAndSettle();

    // The destination's own Key, never a heading the origin button shares —
    // that is what made four M1a navigation tests pass without navigating.
    expect(find.byKey(const Key('submitTitlesScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToSubmitTitles')), findsNothing);
  });

  testWidgets('a faculty member reaches a defence from their dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'l1', 'status': 'titlePendingDefence',
      'panelistUids': <String>['u2'], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
      'titleRound': 1,
    });
    // The dashboard finds defences through the nominations collection group,
    // because faculty cannot list theses.
    await db.collection('theses/t1/nominations').doc('u2').set({
      'nomineeUid': 'u2', 'nomineeName': 'Dr. Test', 'position': 'panelist',
      'exOfficio': false, 'conformeStatus': 'accepted',
    });
    final c = await containerFor('faculty', 'u2', db);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToDefence-t1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToDefence-t1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleDefenceScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToDefence-t1')), findsNothing);
  });
}
