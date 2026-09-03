import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/widgets/app_shell.dart';
import 'package:ethesishub/core/widgets/app_shell_host.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';
import 'package:ethesishub/providers/theme_provider.dart';

const _destinations = [
  ShellDestination(
    label: 'Overview',
    icon: Icons.dashboard_outlined,
    route: '/overview',
  ),
  ShellDestination(
    label: 'Chapters',
    icon: Icons.menu_book_outlined,
    route: '/thesis/chapters',
  ),
];

/// The name long enough to have caused the overflow the reviewer's
/// original report described.
const _longName = 'Engr. Maria Cristina Bautista-Villanueva de la Rosa';

/// IMPORTANT 4 (whole-branch review): spec §5.3 -- "Name, role and
/// sign-out at the foot of the sidebar" -- was implemented nowhere.
/// `app_shell_host.dart` passed a bare `SignOutButton` as the shell's
/// `accountFooter`, so nothing in the chrome said who was signed in or in
/// what capacity.
///
/// [AccountFooter] fixes that, and the constraint carried alongside the
/// finding is load-bearing: nothing may depend on `users/{uid}` existing
/// for the SHELL to render, and that account -- `/no-profile` -- is
/// exactly the one that most needs a working sign-out. So a missing or
/// errored profile must degrade to sign-out alone, never a blank footer
/// and never a thrown exception.
AppUser _user({UserRole role = UserRole.faculty}) => AppUser(
      uid: 'u1',
      fullName: 'Dr. Jane Dela Cruz',
      email: 'jane@isufst.edu.ph',
      role: role,
      active: true,
      createdAt: DateTime(2026),
    );

Future<void> pump(
  WidgetTester tester, {
  required AsyncValue<AppUser?> profile,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(Map.of(prefs));
  final store = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => switch (profile) {
              AsyncData(:final value) => Stream.value(value),
              AsyncError(:final error) => Stream<AppUser?>.error(error),
              _ => const Stream<AppUser?>.empty(),
            }),
        sharedPrefsProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AccountFooter()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('AccountFooter', () {
    testWidgets('shows the signed-in reader\'s name, role and sign-out',
        (tester) async {
      await pump(tester,
          profile: AsyncValue.data(_user(role: UserRole.coordinator)));

      expect(find.byKey(const Key('accountFooterName')), findsOneWidget);
      expect(find.text('Dr. Jane Dela Cruz'), findsOneWidget);
      expect(find.byKey(const Key('accountFooterRole')), findsOneWidget);
      expect(find.text('College Research Coordinator'), findsOneWidget);
      expect(find.byKey(const Key('signOut')), findsOneWidget);
    });

    testWidgets(
        'a missing profile (the /no-profile case) degrades to sign-out '
        'alone -- not a blank footer, not an exception', (tester) async {
      await pump(tester, profile: const AsyncValue.data(null));

      expect(find.byKey(const Key('accountFooterSignOutOnly')), findsOneWidget);
      expect(find.byKey(const Key('accountFooterName')), findsNothing);
      expect(find.byKey(const Key('signOut')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a failed profile read ALSO degrades to sign-out alone, never a '
        'thrown exception', (tester) async {
      await pump(tester,
          profile: AsyncValue.error(StateError('permission-denied'),
              StackTrace.empty));

      expect(find.byKey(const Key('accountFooterSignOutOnly')), findsOneWidget);
      expect(find.byKey(const Key('signOut')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('while the profile is still loading, sign-out alone -- no '
        'crash on the first frame', (tester) async {
      await pump(tester, profile: const AsyncValue.loading());

      expect(find.byKey(const Key('accountFooterSignOutOnly')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the theme toggle sits beside sign-out with a signed-in '
        'profile', (tester) async {
      await pump(tester, profile: AsyncValue.data(_user()));

      expect(find.byKey(const Key('themeToggle')), findsOneWidget);
    });

    testWidgets('the theme toggle is present even when the profile is '
        'missing (the /no-profile case)', (tester) async {
      await pump(tester, profile: const AsyncValue.data(null));

      expect(find.byKey(const Key('themeToggle')), findsOneWidget);
      expect(find.byKey(const Key('accountFooterSignOutOnly')), findsOneWidget);
    });

    testWidgets('tapping the theme toggle cycles system -> light -> dark',
        (tester) async {
      await pump(tester, profile: AsyncValue.data(_user()));

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('themeToggle'))),
      );
      expect(container.read(themeModeProvider), ThemeMode.system);

      await tester.tap(find.byKey(const Key('themeToggle')));
      await tester.pump();
      expect(container.read(themeModeProvider), ThemeMode.light);

      await tester.tap(find.byKey(const Key('themeToggle')));
      await tester.pump();
      expect(container.read(themeModeProvider), ThemeMode.dark);

      await tester.tap(find.byKey(const Key('themeToggle')));
      await tester.pump();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets(
        'a long name does not overflow at a 360px drawer width', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(AppUser(
                uid: 'u1',
                fullName: _longName,
                email: 'maria@isufst.edu.ph',
                role: UserRole.coordinator,
                active: true,
                createdAt: DateTime(2026),
              )),
            ),
            sharedPrefsProvider.overrideWithValue(store),
          ],
          child: const MaterialApp(
            home: Scaffold(
              // 360px here stands in for `NavigationDrawer`'s own fixed
              // width: `NavigationDrawer` lays its children out inside a
              // plain `ListView`, which genuinely bounds their width, so
              // an externally-imposed `SizedBox` is a faithful proxy for
              // that context. It is NOT a faithful proxy for the rail --
              // see the two tests below.
              body: SizedBox(width: 360, child: AccountFooter()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // FINDING 2 (fix round 1 review), part 1: this used to wrap
    // `AccountFooter` in an external `SizedBox(width: 220)`, which bounds
    // the width whether or not `AccountFooter`'s own self-bounding logic
    // works -- and the default test viewport (800x600) is below
    // `AppShell.railBreakpoint` (900) regardless, so `AccountFooter`'s
    // `wide` check evaluated false and the rail code path this test is
    // named after was never even entered. This version removes the
    // artificial `SizedBox` and raises the viewport to the breakpoint, so
    // `AccountFooter` genuinely takes the "I might be in the rail"
    // branch and self-imposes its own width.
    //
    // Caveat, found while falsifying this by neutering the `wide` check:
    // a bare `Scaffold(body: ...)` bounds width to the viewport on its
    // own, same as before the fix -- `NavigationRail`'s specific hazard
    // (a genuinely UNBOUNDED trailing constraint) only exists inside a
    // real `NavigationRail`, which this harness doesn't have. Neutering
    // `wide` here does NOT make this test fail; it only proves the
    // icons-only collapse path is unreachable at this size, which isn't
    // the point. The test below -- a real `AppShell` -- is what actually
    // reaches the hazard and is the one that fails when `wide` is
    // neutered. This one stays as a lighter sanity check on the same
    // code path, not as the falsifying test.
    testWidgets(
        'a long name does not overflow at rail width, with NO external '
        'width bound -- only AccountFooter\'s own self-bounding logic',
        (tester) async {
      tester.view.physicalSize = const Size(AppShell.railBreakpoint, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(AppUser(
                uid: 'u1',
                fullName: _longName,
                email: 'maria@isufst.edu.ph',
                role: UserRole.coordinator,
                active: true,
                createdAt: DateTime(2026),
              )),
            ),
            sharedPrefsProvider.overrideWithValue(store),
          ],
          // No SizedBox, no ConstrainedBox around AccountFooter: the
          // Scaffold body gives it exactly the ambient constraints a real
          // screen would.
          child: const MaterialApp(
            home: Scaffold(body: AccountFooter()),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // The strongest form the review asked for: the real `AccountFooter`,
    // with a real profile, sitting inside a real wide `AppShell` --
    // i.e. actually inside `NavigationRail.trailing`, not a stand-in for
    // it. This is what a genuine `Expanded`-under-unbounded-width crash
    // (the 83-test regression) would have failed.
    testWidgets(
        'the real AccountFooter renders without exception inside a real '
        'wide AppShell', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(AppUser(
                uid: 'u1',
                fullName: _longName,
                email: 'maria@isufst.edu.ph',
                role: UserRole.coordinator,
                active: true,
                createdAt: DateTime(2026),
              )),
            ),
            sharedPrefsProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: AppShell(
              destinations: const AsyncValue.data(_destinations),
              location: '/overview',
              title: 'PAGE TITLE',
              accountFooter: const AccountFooter(),
              child: const Text('PAGE BODY'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('accountFooterName')), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });

  group('shellTitleFor', () {
    test('/overview reads "Overview", matching the sidebar\'s own label -- '
        'not the app name (spec §5.4)', () {
      expect(shellTitleFor('/overview', const {}, UserRole.student),
          'Overview');
    });
  });

  group('AppShellHost', () {
    // Task 10: `AppShellHost.build` now also watches
    // `notificationDetectorsProvider`, which pulls in all five notification
    // detectors (Tasks 5-9). Those detectors need more than the bare
    // `currentUserProvider`/`sharedPrefsProvider` overrides the file's
    // existing `pump()` helper sets up for `AccountFooter` -- they read
    // `firebaseAuthProvider` and `firestoreProvider` all the way down (see
    // `signedInUidProvider`, `myThesisProvider`, `myDefencesProvider`, etc),
    // so this is a small, separate helper scoped to exactly this one test:
    // a real `MockFirebaseAuth`/`FakeFirebaseFirestore` pair, the same
    // pattern `test/providers/notification_detectors_test.dart`'s
    // `containerFor` uses, plus a seeded `users/{uid}` doc so
    // `currentUserProvider` resolves to a real (student) role instead of
    // sitting in `AsyncLoading` forever.
    Future<void> pumpAppShellHost(WidgetTester tester, {required String uid}) async {
      final mockUser =
          MockUser(uid: uid, isEmailVerified: true, email: 'reader@isufst.edu.ph');
      final auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc(uid).set({
        'fullName': 'Reader Dela Cruz',
        'email': 'reader@isufst.edu.ph',
        'role': UserRole.student.value,
        'active': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            sharedPrefsProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            // `AppShellHost.build` never calls `context.go`/`context.pop`
            // itself -- those only fire from inside the `onBack` callback,
            // which this test never taps -- so a plain `MaterialApp` (no
            // real `GoRouter`) is enough to render it once.
            home: const AppShellHost(
              location: '/overview',
              pathParameters: {},
              child: Text('PAGE BODY'),
            ),
          ),
        ),
      );
    }

    testWidgets('watching the shell keeps every notification detector alive',
        (tester) async {
      // Confirms that wiring `notificationDetectorsProvider` into
      // `AppShellHost.build` (Task 10) does not crash shell rendering for a
      // signed-in reader -- a regression here would mean one detector's own
      // bug (e.g. a null role read) breaks shell rendering for every
      // signed-in reader, not just the detector itself.
      await pumpAppShellHost(tester, uid: 'student1');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
