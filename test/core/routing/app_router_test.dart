import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Seeds the stream with the mock's current user immediately (working around
/// firebase_auth_mocks' authStateChanges() being a plain, non-replaying
/// broadcast stream that would otherwise drop the constructor's initial
/// emission), then forwards every subsequent authStateChanges() event (e.g.
/// from a later signOut() call) so tests can observe live auth transitions.
Stream<User?> _seededAuthState(FirebaseAuth auth) async* {
  yield auth.currentUser;
  yield* auth.authStateChanges();
}

Future<ProviderContainer> containerFor(
  UserRole role, {
  required String uid,
  bool isEmailVerified = true,
}) async {
  final db = FakeFirebaseFirestore();
  await UserRepository(db).createStudentProfile(
    uid: uid,
    fullName: 'Test User',
    email: 'test@isufst.edu.ph',
  );
  if (role != UserRole.student) {
    await db.collection('users').doc(uid).update({'role': role.value});
  }

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final mockUser = MockUser(
    uid: uid,
    email: 'test@isufst.edu.ph',
    isEmailVerified: isEmailVerified,
  );

  return ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(
          signedIn: true,
          mockUser: mockUser,
        ),
      ),
      authStateProvider.overrideWith(
        (ref) => _seededAuthState(ref.watch(firebaseAuthProvider)),
      ),
    ],
  );
}

Future<ProviderContainer> containerForSignedOut() async {
  final db = FakeFirebaseFirestore();

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: false),
      ),
      authStateProvider.overrideWith((ref) => Stream.value(null)),
    ],
  );
}

void main() {
  // Every role lands on '/overview' now rather than on a dashboard of its
  // own. What each test below asserts is unchanged -- that the signed-in
  // account is shown ITS role's overview and no other's -- but the
  // per-role dashboards that used to answer that are gone, so the
  // assertion is on the overview body's own key.
  testWidgets('student lands on their own overview', (tester) async {
    final container = await containerFor(UserRole.student, uid: 'u1');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
  });

  testWidgets('faculty lands on their own overview', (tester) async {
    final container = await containerFor(UserRole.faculty, uid: 'u2');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);
    expect(find.byKey(const Key('facultyOverview')), findsOneWidget);
  });

  testWidgets('coordinator lands on their own overview',
      (tester) async {
    final container = await containerFor(UserRole.coordinator, uid: 'u3');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);
    expect(find.byKey(const Key('coordinatorOverview')), findsOneWidget);
  });

  testWidgets('dean lands on their own overview', (tester) async {
    final container = await containerFor(UserRole.dean, uid: 'u4');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);
    expect(find.byKey(const Key('deanOverview')), findsOneWidget);
  });

  testWidgets('a student typing the old /dean path never sees a dean view',
      (tester) async {
    final container = await containerFor(UserRole.student, uid: 'u1');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);

    // '/dean' is a bookmarkable URL that used to be the dean's dashboard.
    // It redirects to '/overview' now, which is itself role-scoped: the
    // guard is no longer "refuse the path" but "the one overview only ever
    // renders the signed-in account's own role" -- which is the property
    // that actually mattered.
    container.read(goRouterProvider).go('/dean');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deanOverview')), findsNothing);
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
  });

  testWidgets(
      'a faculty member typing the old /coordinator path never sees a '
      'coordinator view', (tester) async {
    final container = await containerFor(UserRole.faculty, uid: 'u2');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('facultyOverview')), findsOneWidget);

    container.read(goRouterProvider).go('/coordinator');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coordinatorOverview')), findsNothing);
    expect(find.byKey(const Key('facultyOverview')), findsOneWidget);
  });

  testWidgets('signed-out user can reach registration from sign-in',
      (tester) async {
    final container = await containerForSignedOut();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Should be on Sign in screen
    expect(find.text('Sign in'), findsWidgets);

    // Tap the "goToRegister" button to navigate to registration
    await tester.tap(find.byKey(const Key('goToRegister')));
    await tester.pumpAndSettle();

    // Should be on Create account screen
    expect(find.text('Create account'), findsWidgets);
  });

  testWidgets('signed-out user can get back to sign-in from registration',
      (tester) async {
    final container = await containerForSignedOut();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to registration screen
    container.read(goRouterProvider).go('/register');
    await tester.pumpAndSettle();

    // Should be on Create account screen
    expect(find.text('Create account'), findsWidgets);

    // Scroll it into view first: the register form is taller than the
    // default 800x600 test surface, so the link at the bottom is off-screen
    // and a bare tap misses. (It grew when the testing-mode notice was
    // added above the fields.)
    await tester.ensureVisible(find.byKey(const Key('goToLogin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goToLogin')));
    await tester.pumpAndSettle();

    // Should be back on Sign in screen
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('signing out from a signed-in screen returns to the login screen',
      (tester) async {
    // Sign-out used to be repeated in four dashboards' app bars; it is one
    // control in the shell's account footer now. Wide, because on the
    // narrow layout that footer sits inside the drawer.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = await containerFor(UserRole.student, uid: 'u1');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overviewScreen')), findsOneWidget);

    expect(find.byKey(const Key('signOut')), findsOneWidget,
        reason: 'exactly one sign-out, in the shell, not one per screen');
    await tester.tap(find.byKey(const Key('signOut')));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.byKey(const Key('overviewScreen')), findsNothing);
  });

  // --- BLOCKING 4: guard coverage for the two primary auth redirects ---

  testWidgets('signed-out user navigating to a protected route lands on /login',
      (tester) async {
    final container = await containerForSignedOut();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(goRouterProvider).go('/coordinator');
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.byKey(const Key('overviewScreen')), findsNothing);
    expect(find.byKey(const Key('coordinatorOverview')), findsNothing);
  });

  testWidgets(
      'unverified user navigating to a protected route lands on /verify-email',
      (tester) async {
    final container =
        await containerFor(UserRole.coordinator, uid: 'u6', isEmailVerified: false);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EThesisHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(goRouterProvider).go('/coordinator');
    await tester.pumpAndSettle();

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.byKey(const Key('overviewScreen')), findsNothing);
    expect(find.byKey(const Key('coordinatorOverview')), findsNothing);
  });
}
