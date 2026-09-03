import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/app_shell.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/data/models/user_role.dart';
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
  bool suppressBackControl = false,
  Widget? accountFooter,
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
        suppressBackControl: suppressBackControl,
        accountFooter: accountFooter,
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

Future<void> setViewSize(WidgetTester tester, double width, double height) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Stands in for the real `AccountFooter` (`app_shell_host.dart`), which
/// wires itself to Firebase-backed providers this widget test does not
/// set up. Same shape and the same keys the real widget uses for its full
/// (name + role + sign-out) rendering, so the sweep below is exercising
/// the same layout hazard -- fixed-height content pinned to the bottom of
/// a `NavigationRail` -- without needing a real profile stream.
class _FakeAccountFooter extends StatelessWidget {
  const _FakeAccountFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('accountFooter'),
      padding: EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Jane Reyes', key: Key('accountFooterName')),
                Text(
                  'College Research Coordinator',
                  key: Key('accountFooterRole'),
                ),
              ],
            ),
          ),
          Icon(Icons.logout, key: Key('accountFooterSignOut')),
        ],
      ),
    );
  }
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

    testWidgets('the edge strip toggles the sidebar', (tester) async {
      // As above: NavigationRail keeps the label mounted even when
      // collapsed, so the visible property to assert on is
      // `rail.extended`, not find.text — find.text stays true either
      // way, which is the point of keeping the accessible name.
      //
      // The dedicated `Key('sidebarToggle')` button is gone -- the rail's
      // own edge is now the control (`Key('sidebarEdgeToggle')`).
      await setSize(tester, 1400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chapters'), findsOneWidget);
      NavigationRail rail() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail().extended, isTrue);
      expect(find.byKey(const Key('sidebarToggle')), findsNothing);

      await tester.tap(find.byKey(const Key('sidebarEdgeToggle')));
      await tester.pumpAndSettle();
      expect(rail().extended, isFalse);

      await tester.tap(find.byKey(const Key('sidebarEdgeToggle')));
      await tester.pumpAndSettle();
      expect(rail().extended, isTrue);
    });

    testWidgets('Key(sidebarToggle) no longer exists anywhere',
        (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sidebarToggle')), findsNothing);
    });

    // MINOR (fix round 1 review): the gesture-arena reasoning behind the
    // background `GestureDetector` -- a descendant recognizer (a
    // destination's own `InkWell`) wins over the ancestor for a simple
    // tap -- was verified by the reviewer probing this exact behaviour by
    // hand, but nothing in the suite pinned it. These two tests pin both
    // halves; both were falsified before being trusted (destination tap:
    // set `onDestinationSelected: null` and confirmed `navigatedTo` stayed
    // null; background tap: set the ancestor `onTap: null` and confirmed
    // `extended` stayed true), then restored.
    //
    // One candidate regression the review named -- swapping
    // `HitTestBehavior.translucent` for `.opaque` on the ancestor -- was
    // also tried and does NOT break either test: that distinction only
    // matters for a `Stack` of overlapping siblings (whether a hit
    // continues past the first opaque hit to whatever sits behind it),
    // and this is a plain ancestor wrapping a descendant, not a `Stack`,
    // so it is unaffected either way. Recorded here rather than silently
    // dropped, since the review asked for this specific case.
    testWidgets(
        'tapping a destination in the wide rail navigates and does NOT '
        'toggle the sidebar', (tester) async {
      await setSize(tester, 1400);
      String? navigatedTo;
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        onNavigate: (route) => navigatedTo = route,
      ));
      await tester.pumpAndSettle();

      NavigationRail rail() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail().extended, isTrue);

      await tester.tap(find.text('Chapters'));
      await tester.pumpAndSettle();

      expect(navigatedTo, '/thesis/chapters');
      expect(rail().extended, isTrue); // unchanged -- the tap navigated,
      // it did not fall through to the background toggle.
    });

    testWidgets('tapping empty rail background (below the destinations, '
        'not the edge strip) toggles the sidebar', (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(
        // No accountFooter: `NavigationRail.trailing` is null, so the
        // whole area below the three destinations is genuinely empty --
        // nothing there but the rail's own background and the
        // `GestureDetector` behind it.
        await wrap(destinations: const AsyncValue.data(_destinations)),
      );
      await tester.pumpAndSettle();

      NavigationRail rail() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail().extended, isTrue);

      final railRect = tester.getRect(find.byType(NavigationRail));
      // Well clear of the destination icons/labels, which sit near the
      // top of the rail, and well clear of the edge strip, which is a
      // separate 8px-wide widget entirely outside the rail's own bounds.
      final emptyBackground = Offset(
        railRect.left + railRect.width / 2,
        railRect.bottom - 40,
      );
      await tester.tapAt(emptyBackground);
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

  group('back control on the designated dead end (IMPORTANT minor 3)', () {
    testWidgets(
        'suppressBackControl hides it even on a route no destination owns',
        (tester) async {
      // '/no-profile' owns nothing in any destination list, so
      // isDeeperThanDestination alone always answers true there -- but
      // `AppShellHost._back` can only ever fall through to '/overview',
      // which the redirect immediately bounces back to '/no-profile'. A
      // control that does nothing is exactly what this milestone exists
      // to remove.
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data([]),
        location: '/no-profile',
        suppressBackControl: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellBack')), findsNothing);
    });

    testWidgets('without suppression, the same route WOULD show a back '
        'control -- proving the flag is load-bearing', (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data([]),
        location: '/no-profile',
        suppressBackControl: false,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shellBack')), findsOneWidget);
    });

    testWidgets('a genuinely deep route elsewhere is unaffected',
        (tester) async {
      await setSize(tester, 1400);
      await tester.pumpWidget(await wrap(
        destinations: const AsyncValue.data(_destinations),
        location: '/thesis/chapters/chapterIII',
        suppressBackControl: false,
      ));
      await tester.pumpAndSettle();

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

  group('short-rail account footer', () {
    // Coordinator: six destinations, the worst case for how much vertical
    // space the rail's own content claims before the footer gets a turn.
    final coordinatorDestinations = destinationsFor(role: UserRole.coordinator);
    assert(coordinatorDestinations.length == 6); // guards the "worst case" claim

    for (final height in [320.0, 420.0, 600.0, 1000.0]) {
      testWidgets('rail height=$height overflows nothing', (tester) async {
        await setViewSize(tester, 1400, height);
        await tester.pumpWidget(await wrap(
          destinations: AsyncValue.data(coordinatorDestinations),
          accountFooter: const _FakeAccountFooter(),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'at a normal height the full footer renders and sits at the foot '
        'of the sidebar', (tester) async {
      await setViewSize(tester, 1400, 1000);
      await tester.pumpWidget(await wrap(
        destinations: AsyncValue.data(coordinatorDestinations),
        accountFooter: const _FakeAccountFooter(),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Jane Reyes'), findsOneWidget);
      expect(find.text('College Research Coordinator'), findsOneWidget);

      // Bottom-aligned: the footer's bottom edge sits near the bottom of
      // the 1000px-tall screen, not directly beneath the last destination.
      final footerBottom =
          tester.getBottomLeft(find.byKey(const Key('accountFooter'))).dy;
      expect(footerBottom, greaterThan(900));
      expect(footerBottom, lessThanOrEqualTo(1000));
    });

    testWidgets('a collapsed (72px) rail does not overflow horizontally',
        (tester) async {
      await setViewSize(tester, 1400, 1000);
      await tester.pumpWidget(await wrap(
        destinations: AsyncValue.data(coordinatorDestinations),
        accountFooter: const _FakeAccountFooter(),
        prefs: {'sidebar_expanded': false},
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('content width when the sidebar collapses', () {
    // Proves point 2 with a measurement, not just a rebuild: at the SAME
    // fixed viewport, collapsing the rail must free real width for a
    // `PageShell`-style dashboard body to grow into, not just recentre in
    // the same box.
    Future<double> probeWidth(
      WidgetTester tester, {
      required bool expanded,
      double viewport = 1400,
    }) async {
      SharedPreferences.setMockInitialValues({'sidebar_expanded': expanded});
      final store = await SharedPreferences.getInstance();
      await setSize(tester, viewport);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppShell(
            destinations: const AsyncValue.data(_destinations),
            location: '/overview',
            title: 'PAGE TITLE',
            child: PageShell(
              maxWidth: AppTokens.measureWide,
              children: const [
                SizedBox(height: 10, key: Key('widthProbe')),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const Key('widthProbe'))).width;
    }

    testWidgets('is wider collapsed than expanded, at a fixed viewport',
        (tester) async {
      final expandedWidth = await probeWidth(tester, expanded: true);
      final collapsedWidth = await probeWidth(tester, expanded: false);

      expect(collapsedWidth, greaterThan(expandedWidth));
      expect(collapsedWidth, lessThanOrEqualTo(AppTokens.measureWide));
    });

    // FINDING 1 (fix round 1 review): the test above passes at ANY
    // `measureWide` value at or above the collapsed width -- 1180 or 1440
    // alike -- because it only ever compares collapsed-vs-expanded at one
    // viewport. It guards "collapsing grows the content," which is a real,
    // separate property, but nothing pinned the cap's actual VALUE, so
    // reverting `AppTokens.measureWide` to 1180 would break nothing here.
    //
    // A viewport wide enough that NEITHER rail state's leftover space is
    // the binding constraint makes the token itself the only thing left
    // that can be capping the probe. At 2000px: collapsed leaves
    // 2000 - (collapsedRailWidth + edge strip) = 1920 available, expanded
    // leaves 2000 - (expandedRailWidth + edge strip) = 1772 -- both well
    // past `measureWide` (1440), so the rail state genuinely is
    // irrelevant, unlike at a viewport merely wider than the cap alone.
    //
    // `PageShell` pads its content by `AppTokens.lg` on each side inside
    // the `ConstrainedBox` that applies `maxWidth`, so the probe (which
    // fills `PageShell`'s own stretched content width) sits at
    // `measureWide` minus that padding, not at `measureWide` itself --
    // the expected value below is exact, not an inequality, so a changed
    // token moves this test's failure, not just its margin.
    for (final expanded in [true, false]) {
      testWidgets(
          'caps at exactly measureWide regardless of rail state '
          '(expanded=$expanded)', (tester) async {
        final width =
            await probeWidth(tester, expanded: expanded, viewport: 2000);

        expect(width, AppTokens.measureWide - (2 * AppTokens.lg));
      });
    }
  });
}
