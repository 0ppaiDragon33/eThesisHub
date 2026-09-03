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

/// Mirrors m1a_routes_test.dart's `containerFor`/`pumpApp` -- a real
/// ProviderContainer standing up the actual `goRouterProvider`, so
/// navigation here goes through the real `GoRoute` table rather than
/// around it via `destinationsFor`/`isDeepForRole` alone.
Future<ProviderContainer> containerFor(String role, String uid) async {
  final firestore = FakeFirebaseFirestore();
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

Future<void> pumpApp(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
  await tester.pumpAndSettle();
}

void main() {
  // Falsification target for Task 11's ordering hazard: '/archive/queue'
  // and '/archive/:thesisId' are both two segments, so a dynamic
  // parameter at position 2 would swallow the literal 'queue' if the
  // GoRoute entries were ever reordered. destinationsFor()/isDeepForRole()
  // are pure logic over the destination LIST and never build the real
  // GoRouter, so neither of them can catch that regression -- only a test
  // that drives the actual router can. This one does.
  testWidgets(
      'a coordinator navigating to /archive/queue reaches the queue '
      'screen, not the entry screen for thesisId "queue"', (tester) async {
    final c = await containerFor('coordinator', 'u1');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/archive/queue');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archiveQueue')), findsOneWidget);
    expect(find.byKey(const Key('archiveEntry')), findsNothing);
  });
}
