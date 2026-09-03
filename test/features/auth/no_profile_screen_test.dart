import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/features/auth/no_profile_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Signed in, but with no `users/{uid}` document written to [db]. The read
/// succeeds and comes back empty -- the "registration did not finish" case.
Future<Widget> wrapNoProfile(FakeFirebaseFirestore db,
    {required String uid}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: const MaterialApp(home: NoProfileScreen()),
  );
}

/// Signed in, but the profile read itself fails. `fake_cloud_firestore`
/// enforces no security rules and so cannot be made to produce a
/// `permission-denied` -- there is no rules engine to refuse the read -- so
/// the failure is faked at the provider level instead, by overriding
/// [currentUserProvider] directly with an [AsyncError].
Future<Widget> wrapNoProfileWithError(Object error) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      sharedPrefsProvider.overrideWithValue(prefs),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'u1', email: 'u1@isufst.edu.ph', isEmailVerified: true),
      )),
      currentUserProvider.overrideWith(
        (ref) => Stream<AppUser?>.error(error),
      ),
    ],
    child: const MaterialApp(home: NoProfileScreen()),
  );
}

void main() {
  testWidgets('an absent profile says the record is missing', (tester) async {
    // The read succeeded and the document is not there. This means
    // registration did not finish — a different problem from a failed
    // read, with a different remedy, and collapsing the two into
    // "something went wrong" is what sent this project hunting a network
    // problem that did not exist.
    final db = FakeFirebaseFirestore(); // no users/{uid} written
    await tester.pumpWidget(await wrapNoProfile(db, uid: 'u1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noProfileScreen')), findsOneWidget);
    expect(find.textContaining('profile record is missing'), findsOneWidget);
  });

  testWidgets('an absent profile offers a way out', (tester) async {
    // Without sign-out this account is trapped: no destination is
    // reachable and no other account can be signed into. That turns a
    // data problem into a support call.
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(await wrapNoProfile(db, uid: 'u1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signOut')), findsOneWidget);
    expect(find.byKey(const Key('noProfileRetry')), findsOneWidget);
  });

  testWidgets('a failed read shows the Firestore code, not the absent copy',
      (tester) async {
    // Override currentUserProvider with an error rather than faking a
    // Firestore failure: fake_cloud_firestore enforces no rules and
    // cannot produce a permission-denied.
    await tester.pumpWidget(await wrapNoProfileWithError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('errorCode')), findsOneWidget);
    expect(find.textContaining('profile record is missing'), findsNothing);
  });

  testWidgets('never renders a dashboard', (tester) async {
    // Spec D25. The failure mode is not a crash — it is the app quietly
    // choosing a role and looking like it works.
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(await wrapNoProfile(db, uid: 'u1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('studentOverview')), findsNothing);
    expect(find.byKey(const Key('deanOverview')), findsNothing);
  });
}
