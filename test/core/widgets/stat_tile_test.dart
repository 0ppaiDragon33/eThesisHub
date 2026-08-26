import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';

Widget wrap(Widget child, {double width = 260}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  testWidgets('renders label, value and unit', (tester) async {
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Chapters approved',
      value: '2',
      unit: '/ 5',
      icon: Icons.check,
      accent: AppTokens.accentPine,
    )));

    expect(find.text('Chapters approved'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('/ 5'), findsOneWidget);
  });

  testWidgets('the value is set in the document serif', (tester) async {
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Active theses',
      value: '18',
      icon: Icons.book_outlined,
      accent: AppTokens.accentPlum,
    )));

    final value = tester.widget<Text>(find.text('18'));
    expect(value.style?.fontFamily, AppTheme.serif);
  });

  testWidgets('the label is NOT set in the serif', (tester) async {
    // Spec D19: the second family is for the document voice only. A serif
    // label at 13px reads as small rather than as considered, and if this
    // ever flips the whole point of bundling two families is lost.
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Active theses',
      value: '18',
      icon: Icons.book_outlined,
      accent: AppTokens.accentPlum,
    )));

    final label = tester.widget<Text>(find.text('Active theses'));
    expect(label.style?.fontFamily, isNot(AppTheme.serif));
  });

  testWidgets('steps down below the compact threshold', (tester) async {
    // The user-visible complaint this widget exists to fix: at phone width
    // four tiles must still fit two-across, which is only survivable if the
    // padding and the value shrink with them.
    Future<double> paddingAt(double width) async {
      await tester.pumpWidget(wrap(
        const StatTile(
          label: 'Active theses',
          value: '18',
          icon: Icons.book_outlined,
          accent: AppTokens.accentPlum,
        ),
        width: width,
      ));
      final padding = tester.widget<Padding>(
        find.byKey(const Key('statTilePadding')),
      );
      return (padding.padding as EdgeInsets).left;
    }

    expect(await paddingAt(260), 22);
    expect(await paddingAt(160), 14);
  });

  testWidgets('renders a progress bar instead of a caption when given one',
      (tester) async {
    await tester.pumpWidget(wrap(const StatTile(
      label: 'Chapters approved',
      value: '2',
      unit: '/ 5',
      caption: 'should be suppressed',
      progress: 0.4,
      icon: Icons.check,
      accent: AppTokens.accentPine,
    )));

    expect(find.byKey(const Key('statTileBar')), findsOneWidget);
    expect(find.text('should be suppressed'), findsNothing);
  });

  testWidgets('a loading tile shows a skeleton, NOT a zero', (tester) async {
    // This project has shipped "0 is indistinguishable from loading" four
    // times. A tile that renders 0 while its stream is in flight tells the
    // reader nothing is waiting when something may well be.
    final controller = StreamController<int>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, ref, _) {
        final async = ref.watch(StreamProvider<int>((_) => controller.stream));
        return wrap(AsyncStatTile<int>(
          label: 'Active theses',
          value: async,
          format: (n) => '$n',
          icon: Icons.book_outlined,
          accent: AppTokens.accentPlum,
        ));
      }),
    ));

    // Single pump, NOT pumpAndSettle: settling would resolve the stream and
    // the assertion would observe the loaded state instead.
    await tester.pump();

    expect(find.byKey(const Key('statTileSkeleton')), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  Future<void> mixedContentSharesOneHeight(
    WidgetTester tester, {
    required bool compact,
    required double width,
  }) async {
    // This is exactly the mechanism StatTileGrid uses: every tile is told
    // its step (so none of them runs its own LayoutBuilder) and the row is
    // wrapped in IntrinsicHeight, which is only legal because none of them
    // does. Three same-width, same-step tiles with different trailing
    // content (a caption line, a progress bar, nothing) have different
    // natural heights on their own; IntrinsicHeight is what makes them
    // share one.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: width,
                child: StatTile(
                  label: 'Has a caption',
                  value: '1',
                  caption: 'Some caption text',
                  icon: Icons.check,
                  accent: AppTokens.accentPine,
                  compact: compact,
                ),
              ),
              SizedBox(
                width: width,
                child: StatTile(
                  label: 'Has a progress bar',
                  value: '2',
                  progress: 0.5,
                  icon: Icons.check,
                  accent: AppTokens.accentSeal,
                  compact: compact,
                ),
              ),
              SizedBox(
                width: width,
                child: StatTile(
                  label: 'Has neither',
                  value: '3',
                  icon: Icons.check,
                  accent: AppTokens.accentOchre,
                  compact: compact,
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    double heightOf(String label) => tester
        .getSize(find.ancestor(
          of: find.text(label),
          matching: find.byType(StatTile),
        ))
        .height;

    final withCaption = heightOf('Has a caption');
    final withProgress = heightOf('Has a progress bar');
    final withNeither = heightOf('Has neither');

    expect(withProgress, withCaption);
    expect(withNeither, withCaption);
  }

  testWidgets(
      'tiles with different content -- caption, progress, neither -- '
      'share one height in a row, at the normal step', (tester) async {
    await mixedContentSharesOneHeight(tester, compact: false, width: 260);
  });

  testWidgets(
      'tiles with different content -- caption, progress, neither -- '
      'share one height in a row, at the compact step', (tester) async {
    await mixedContentSharesOneHeight(tester, compact: true, width: 160);
  });

  testWidgets(
      'a label and caption that both wrap to two lines do not overflow',
      (tester) async {
    // The regression this task exists to close: maxLines: 2 only bounds
    // text HORIZONTALLY via the ellipsis -- it still reserves up to two
    // full line-heights vertically. A fixed card height clipped this;
    // nothing in lib/ today triggers it (every caption shipped so far is
    // one line), but a caption like "Opens once Chapter III is approved"
    // will wrap at these widths once later dashboards add one.
    const tile = StatTile(
      label: 'A label long enough that it wraps onto a second line',
      value: '3',
      caption: 'A caption long enough that it also wraps onto a second line',
      icon: Icons.check,
      accent: AppTokens.accentPine,
    );

    await tester.pumpWidget(wrap(tile, width: 260));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(wrap(tile, width: 160));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an errored tile shows a dash, not a zero', (tester) async {
    await tester.pumpWidget(wrap(AsyncStatTile<int>(
      label: 'Active theses',
      value: AsyncValue.error(Exception('denied'), StackTrace.empty),
      format: (n) => '$n',
      icon: Icons.book_outlined,
      accent: AppTokens.accentPlum,
    )));

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
