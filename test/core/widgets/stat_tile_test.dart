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

  testWidgets(
      'tiles with different content -- caption, progress, neither -- '
      'share one height in a row', (tester) async {
    // The whole reason StatTile's height must be fixed rather than a
    // minimum: three same-width, same-step tiles with different trailing
    // content (a caption line, a progress bar, nothing) previously landed
    // at different natural heights, and the grid's Row then centred them
    // against each other instead of sharing a baseline.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SizedBox(
              width: 260,
              child: StatTile(
                label: 'Has a caption',
                value: '1',
                caption: 'Some caption text',
                icon: Icons.check,
                accent: AppTokens.accentPine,
              ),
            ),
            SizedBox(
              width: 260,
              child: StatTile(
                label: 'Has a progress bar',
                value: '2',
                progress: 0.5,
                icon: Icons.check,
                accent: AppTokens.accentSeal,
              ),
            ),
            SizedBox(
              width: 260,
              child: StatTile(
                label: 'Has neither',
                value: '3',
                icon: Icons.check,
                accent: AppTokens.accentOchre,
              ),
            ),
          ],
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
