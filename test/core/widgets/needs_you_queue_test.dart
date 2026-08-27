import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';

const _chapter = NeedsYouItem(
  title: 'Chapter III — Methodology',
  detail: 'Returned by Dr. Armada · 2 days ago',
  route: '/thesis/chapters?id=t1',
  chipLabel: 'Revise',
  tone: NeedsYouTone.returned,
);

const _nomination = NeedsYouItem(
  title: 'Panel nomination — Bautista et al.',
  detail: 'Your Conforme requested',
  route: '/nominations',
  chipLabel: 'Reply',
  tone: NeedsYouTone.act,
);

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('renders one row per item', (tester) async {
    await tester.pumpWidget(wrap(const NeedsYouQueue(
      items: AsyncValue.data([_chapter, _nomination]),
      emptyTitle: 'Nothing needs you',
      emptyMessage: 'Anything waiting on you appears here.',
    )));

    expect(find.text('Chapter III — Methodology'), findsOneWidget);
    expect(find.text('Panel nomination — Bautista et al.'), findsOneWidget);
    expect(find.text('Revise'), findsOneWidget);
  });

  testWidgets('an empty queue says so rather than rendering blank',
      (tester) async {
    await tester.pumpWidget(wrap(const NeedsYouQueue(
      items: AsyncValue.data([]),
      emptyTitle: 'Nothing needs you',
      emptyMessage: 'Anything waiting on you appears here.',
    )));

    expect(find.text('Nothing needs you'), findsOneWidget);
  });

  testWidgets('a loading queue is distinguishable from an empty one',
      (tester) async {
    final controller = StreamController<List<NeedsYouItem>>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, ref, _) {
        final async = ref.watch(
          StreamProvider<List<NeedsYouItem>>((_) => controller.stream),
        );
        return wrap(NeedsYouQueue(
          items: async,
          emptyTitle: 'Nothing needs you',
          emptyMessage: 'Anything waiting on you appears here.',
        ));
      }),
    ));

    // Single pump: pumpAndSettle would resolve the stream first and the
    // assertion would observe the loaded state.
    await tester.pump();

    expect(find.text('Nothing needs you'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the headline count equals the number of rows rendered',
      (tester) async {
    // Spec D16. Two sources for this number would eventually disagree, and
    // a dashboard that contradicts itself is worse than one showing nothing.
    const items = AsyncValue<List<NeedsYouItem>>.data([_chapter, _nomination]);

    await tester.pumpWidget(wrap(const Column(children: [
      NeedsYouHeadline(items: items, suffix: 'Second semester'),
      NeedsYouQueue(
        items: items,
        emptyTitle: 'Nothing needs you',
        emptyMessage: 'Anything waiting on you appears here.',
      ),
    ])));

    expect(find.textContaining('2 things need you today'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('the headline is singular for one item', (tester) async {
    await tester.pumpWidget(wrap(const NeedsYouHeadline(
      items: AsyncValue.data([_chapter]),
      suffix: 'Second semester',
    )));

    expect(find.textContaining('1 thing needs you today'), findsOneWidget);
  });

  testWidgets('the headline does not claim zero while loading',
      (tester) async {
    final controller = StreamController<List<NeedsYouItem>>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, ref, _) {
        final async = ref.watch(
          StreamProvider<List<NeedsYouItem>>((_) => controller.stream),
        );
        return wrap(NeedsYouHeadline(items: async, suffix: 'Second semester'));
      }),
    ));
    await tester.pump();

    expect(find.textContaining('0 things'), findsNothing);
    expect(find.textContaining('Nothing needs you'), findsNothing);
  });

  group('push vs go by NeedsYouItem.deep (Task 9 fix round 1)', () {
    // Drives a real GoRouter, the way test/core/routing/deep_navigation_
    // test.dart does for the five call sites Task 9 named -- this row's
    // "Open" button was the one call site the brief's own file list did
    // not name, and it went unexercised by any test.
    //
    // The observable consequence asserted here is whether the list route
    // survives beneath the one navigated to: `context.push` appends a new
    // entry onto go_router's Navigator so `Navigator.canPop` reads true
    // once the new screen is up; `context.go` replaces the whole match
    // list for a flat top-level route like the ones below, so nothing is
    // left to pop back to. A "which method fired" assertion would not
    // catch the ternary in needs_you_queue.dart being flipped; this one
    // does, because it reads the Navigator's own state rather than a
    // stand-in for it.
    const deepItem = NeedsYouItem(
      title: 'Deep item',
      detail: 'Targets a screen below a destination',
      route: '/deep',
      chipLabel: 'Open',
      tone: NeedsYouTone.act,
      deep: true,
    );
    const shallowItem = NeedsYouItem(
      title: 'Shallow item',
      detail: 'Targets a destination',
      route: '/other',
      chipLabel: 'Open',
      tone: NeedsYouTone.act,
      deep: false,
    );

    Future<GoRouter> pumpRoutedQueue(
      WidgetTester tester, {
      required List<NeedsYouItem> items,
    }) async {
      final router = GoRouter(
        initialLocation: '/list',
        routes: [
          GoRoute(
            path: '/list',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: NeedsYouQueue(
                  items: AsyncValue.data(items),
                  emptyTitle: 'Nothing needs you',
                  emptyMessage: 'Anything waiting on you appears here.',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/deep',
            builder: (_, _) => const Scaffold(body: Text('DEEP SCREEN')),
          ),
          GoRoute(
            path: '/other',
            builder: (_, _) => const Scaffold(body: Text('OTHER SCREEN')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    /// The button inside the row titled [title].
    Finder openButtonFor(String title) => find.descendant(
          of: find.widgetWithText(ListTile, title),
          matching: find.widgetWithText(FilledButton, 'Open'),
        );

    testWidgets(
        'a deep item pushes: the list survives beneath the pushed screen',
        (tester) async {
      await pumpRoutedQueue(tester, items: const [deepItem]);

      await tester.tap(openButtonFor('Deep item'));
      await tester.pumpAndSettle();

      expect(find.text('DEEP SCREEN'), findsOneWidget);
      final canPop =
          Navigator.of(tester.element(find.text('DEEP SCREEN'))).canPop();
      expect(canPop, isTrue,
          reason: 'a deep item must push, leaving the list mounted beneath '
              'it -- go would replace it, and nothing would be left to '
              'pop back to');
    });

    testWidgets(
        'a non-deep item goes: nothing is left in the stack to pop back to',
        (tester) async {
      await pumpRoutedQueue(tester, items: const [shallowItem]);

      await tester.tap(openButtonFor('Shallow item'));
      await tester.pumpAndSettle();

      expect(find.text('OTHER SCREEN'), findsOneWidget);
      final canPop =
          Navigator.of(tester.element(find.text('OTHER SCREEN'))).canPop();
      expect(canPop, isFalse,
          reason: 'a non-deep (destination) item must go, replacing the '
              'list rather than stacking onto it -- push here would give '
              'the sidebar a growing history to pop through, which Task 9 '
              'forbids');
    });
  });
}
