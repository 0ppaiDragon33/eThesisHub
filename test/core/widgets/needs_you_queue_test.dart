import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
