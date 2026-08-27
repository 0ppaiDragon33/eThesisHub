import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/core/widgets/app_shell_host.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';
import 'package:ethesishub/providers/theme_provider.dart';

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
                fullName:
                    'Engr. Maria Cristina Bautista-Villanueva de la Rosa',
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
              body: SizedBox(width: 360, child: AccountFooter()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a long name does not overflow at a 220px rail width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => Stream.value(AppUser(
                uid: 'u1',
                fullName:
                    'Engr. Maria Cristina Bautista-Villanueva de la Rosa',
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
              body: SizedBox(width: 220, child: AccountFooter()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('shellTitleFor', () {
    test('/overview reads "Overview", matching the sidebar\'s own label -- '
        'not the app name (spec §5.4)', () {
      expect(shellTitleFor('/overview', const {}, UserRole.student),
          'Overview');
    });
  });
}
