import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Mirrors archive_routes_test.dart's `containerFor`/`pumpApp`: a real
/// ProviderContainer standing up the actual `goRouterProvider`, so
/// navigating to '/forms' goes through the real `GoRoute` table rather
/// than around it.
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
  // Requirement test 4, first half: '/forms' resolves to the Forms screen,
  // through the real GoRouter table, not merely `destinationsFor` logic,
  // which cannot catch a route missing from `app_router.dart` at all.
  testWidgets('/forms resolves to the Forms screen', (tester) async {
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/forms');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forms')), findsOneWidget);
  });

  // Typing the address does not bring the library back for the others.
  for (final role in ['faculty', 'coordinator', 'dean']) {
    testWidgets('$role is sent home from /forms', (tester) async {
      final c = await containerFor(role, 'u1');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      c.read(goRouterProvider).go('/forms');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forms')), findsNothing);
    });
  }

  // Requirement test 4, second half: '/forms' is a destination for a
  // student, and for no one else. The library is a student's page; the
  // others reach the forms they fill in from the screen that asks for them.
  test('/forms is a destination for a student alone', () {
    for (final role in UserRole.values) {
      final routes =
          destinationsFor(role: role).map((d) => d.route).toList();
      if (role == UserRole.student) {
        expect(routes, contains('/forms'), reason: role.name);
      } else {
        expect(routes, isNot(contains('/forms')), reason: role.name);
      }
    }
  });
}
