import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/widgets/app_shell.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

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
  ShellDestination(
    label: 'Defences',
    icon: Icons.event_note_outlined,
    route: '/defences',
  ),
];

Future<Widget> wrap({
  required AsyncValue<List<ShellDestination>> destinations,
  String location = '/overview',
  ValueChanged<String>? onNavigate,
  VoidCallback? onBack,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(Map.of(prefs));
  final store = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(store)],
    child: MaterialApp(
      theme: AppTheme.light,
      home: AppShell(
        destinations: destinations,
        location: location,
        title: 'PAGE TITLE',
        onNavigate: onNavigate,
        onBack: onBack,
        child: const Text('PAGE BODY'),
      ),
    ),
  );
}

Future<void> setSize(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('wide', () {
    testWidgets('shows labels when expanded', (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chapters'), findsOneWidget);
      expect(find.text('PAGE BODY'), findsOneWidget);
    });

    testWidgets('hides labels when collapsed but keeps the destinations',
        (tester) async {
      // `NavigationRail` deliberately keeps a collapsed destination's
      // label mounted (Visibility.maintain) so it stays in the
      // accessibility tree — find.text would therefore still match it
      // even though nothing is painted. What "collapsed" must actually
      // mean is: visually collapsed (rail.extended == false), the icon
      // still there, and the accessible name still carried, since a
      // screen-reader user gets nothing else to tell destinations apart.
      final handle = tester.ensureSemantics();

      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        prefs: {'sidebar_expanded': false},
      ));
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);

      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      final semantics =
          tester.getSemantics(find.byIcon(Icons.menu_book_outlined));
      expect(semantics.label, contains('Chapters'));

      // Disposed explicitly, not via addTearDown: the framework's
      // end-of-test semantics-handle check runs before addTearDown
      // callbacks fire, so a handle only released there is still flagged
      // as leaked.
      handle.dispose();
    });

    testWidgets('the chevron toggles the sidebar', (tester) async {
      // As above: NavigationRail keeps the label mounted even when
      // collapsed, so the visible property to assert on is
      // `rail.extended`, not find.text — find.text stays true either
      // way, which is the point of keeping the accessible name.
      await setSize(tester, 1400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chapters'), findsOneWidget);
      NavigationRail rail() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail().extended, isTrue);

      await tester.tap(find.byKey(const Key('sidebarToggle')));
      await tester.pumpAndSettle();
      expect(rail().extended, isFalse);
    });

    testWidgets('has no hamburger — the sidebar is already visible',
        (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      // R3: assert by key, not by the default tooltip string — a custom
      // tooltip would silently make the original assertion pass for the
      // wrong reason.
      expect(find.byKey(const Key('shellMenu')), findsNothing);
    });
  });

  group('narrow', () {
    testWidgets('shows a hamburger and NO bottom bar', (tester) async {
      // The specific complaint this milestone answers: with a bottom bar
      // there was nothing on an inner screen, and six destinations
      // overflowed it anyway.
      await setSize(tester, 400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellMenu')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Chapters'), findsNothing); // drawer is closed
    });

    testWidgets('the hamburger opens a drawer with the destinations',
        (tester) async {
      await setSize(tester, 400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shellMenu')));
      await tester.pumpAndSettle();

      expect(find.text('Chapters'), findsOneWidget);
    });

    testWidgets('selecting in the drawer navigates AND closes it',
        (tester) async {
      await setSize(tester, 400);
      String? navigatedTo;
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        onNavigate: (route) => navigatedTo = route,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shellMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapters'));
      await tester.pumpAndSettle();

      expect(navigatedTo, '/thesis/chapters');
      // A drawer left open over the screen you just navigated to is the
      // bug this asserts against.
      expect(find.text('Chapters'), findsNothing);
    });
  });

  group('role resolution', () {
    testWidgets('while loading, renders chrome and NO tappable destination',
        (tester) async {
      // Spec D26. A skeleton cannot misroute, because there is nothing to
      // tap. A guessed role can offer a destination the account does not
      // hold, and tapping it produces a permission-denied the reader
      // cannot act on.
      await setSize(tester, 1400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.loading()),
      );
      // Single pump: settling would let any animation resolve and is not
      // needed to observe the loading branch.
      await tester.pump();

      expect(find.byKey(const Key('shellSkeleton')), findsOneWidget);
      expect(find.text('Overview'), findsNothing);
      expect(find.text('PAGE BODY'), findsOneWidget);
    });

    testWidgets(
        'while loading on narrow width, shows a hamburger whose drawer '
        'holds the skeleton', (tester) async {
      // On a phone the loading state must not be bare chrome with nothing
      // in it — the hamburger stays present so the reader can see
      // navigation is coming, and opening it finds the same inert
      // skeleton rather than an empty drawer.
      await setSize(tester, 400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.loading()),
      );
      await tester.pump();

      expect(find.byKey(const Key('shellMenu')), findsOneWidget);
      expect(find.byKey(const Key('shellSkeleton')), findsNothing);

      await tester.tap(find.byKey(const Key('shellMenu')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellSkeleton')), findsOneWidget);
    });

    testWidgets('with no destinations, renders the child and no sidebar',
        (tester) async {
      // The no-profile case: an empty sidebar is the honest statement,
      // because the app genuinely does not know what this account reaches.
      await setSize(tester, 1400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data([])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byKey(const Key('shellMenu')), findsNothing);
      expect(find.text('PAGE BODY'), findsOneWidget);
    });

    testWidgets('below two destinations, no navigation is offered',
        (tester) async {
      // The rule ResponsiveScaffold established and this widget inherits:
      // a control that does nothing when tapped reads as a broken app.
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: AsyncValue.data([_destinations.first]),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('back control', () {
    testWidgets('absent on a destination route', (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/thesis/chapters',
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellBack')), findsNothing);
    });

    testWidgets('present on a route nested under a destination',
        (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/thesis/chapters/chapterIII',
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellBack')), findsOneWidget);
    });

    testWidgets('present on a route no destination owns', (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/defence/room/d1',
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellBack')), findsOneWidget);
    });

    testWidgets(
        'with no onBack supplied, tapping it does not crash when there is '
        'nothing to pop', (tester) async {
      // The default falls back to `Navigator.maybePop`, not `Navigator.
      // pop` -- a deep screen reached directly by URL has nothing beneath
      // it in this Navigator (AppShell is the sole route under
      // MaterialApp's `home`), and `pop` would throw where `maybePop`
      // simply does nothing.
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/defence/room/d1',
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shellBack')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping it calls onBack', (tester) async {
      await setSize(tester, 1400);
      var backs = 0;
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/defence/room/d1',
        onBack: () => backs++,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shellBack')));
      expect(backs, 1);
    });

    // R1: on mobile the hamburger must stay put even on a deep screen, so
    // navigation is never one back-tap away from being lost. The back
    // control lives in `actions` alongside it, never replacing it.
    testWidgets(
        'at narrow width on a deep location, both the hamburger and back '
        'control are present', (tester) async {
      await setSize(tester, 400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/defence/room/d1',
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellMenu')), findsOneWidget);
      expect(find.byKey(const Key('shellBack')), findsOneWidget);
    });
  });

  group('highlighting', () {
    testWidgets('a nested route highlights its owning destination',
        (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/thesis/chapters/chapterIII',
      ));
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 1); // Chapters
    });

    testWidgets('an unowned route highlights nothing', (tester) async {
      // Spec D24: a wrong highlight tells the reader they are somewhere
      // they are not, which is worse than no highlight.
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/defence/room/d1',
      ));
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, isNull);
    });
  });
}
