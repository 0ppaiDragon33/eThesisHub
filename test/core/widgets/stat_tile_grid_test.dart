import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';
import 'package:ethesishub/core/widgets/stat_tile_grid.dart';

Widget four() => StatTileGrid(children: [
      for (var i = 0; i < 4; i++)
        StatTile(
          label: 'Tile $i',
          value: '$i',
          icon: Icons.circle,
          accent: AppTokens.accents[i],
        ),
    ]);

/// How many distinct x-offsets the tiles occupy — i.e. how many columns.
int columnsOf(WidgetTester tester) {
  final xs = <double>{};
  for (var i = 0; i < 4; i++) {
    xs.add(tester.getTopLeft(find.text('Tile $i')).dx);
  }
  return xs.length;
}

Future<void> pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: four())),
  ));
  await tester.pump();
}

void main() {
  testWidgets('four across on a desktop', (tester) async {
    await pumpAt(tester, 1400);
    expect(columnsOf(tester), 4);
  });

  testWidgets('two across on a tablet', (tester) async {
    await pumpAt(tester, 700);
    expect(columnsOf(tester), 2);
  });

  testWidgets('still two across on a 360px phone, never one', (tester) async {
    // The whole point. A 216px minimum would give a single stacked column
    // here -- four tall cards and a screenful of scrolling -- which is what
    // the first draft of this design would have shipped.
    await pumpAt(tester, 360);
    expect(columnsOf(tester), 2);
  });

  testWidgets('tiles stop widening past the measure', (tester) async {
    // Four equal columns across a very wide monitor is what produced the
    // long flat strips. The row caps rather than smearing. The bound is
    // derived from `AppTokens.measureWide` (not a bare number) so this
    // stays true if that token moves again -- it already has once, when
    // the sidebar collapse was given real room to grow the content into.
    await pumpAt(tester, 2400);
    final tile = tester.getSize(find.ancestor(
      of: find.text('Tile 0'),
      matching: find.byType(StatTile),
    ));
    expect(tile.width, lessThan(AppTokens.measureWide / 4));
  });

  testWidgets('column count never decreases as the window widens',
      (tester) async {
    // An earlier version derived a raw column count from minTileWidth and
    // then vetoed it with a second, unrelated rule (StatTile.compactBelow).
    // The two rules disagreed over 648px-848px: 3 columns at 640, 2 at 648,
    // 4 at 848 -- the count visibly flickered as a window was dragged
    // through that range. None of the four fixed-width tests above land in
    // it, so only a sweep catches it.
    var previous = 0;
    for (var width = 360.0; width <= 1600; width += 20) {
      await pumpAt(tester, width);
      final columns = columnsOf(tester);
      expect(
        columns,
        greaterThanOrEqualTo(previous),
        reason: 'columns dropped at width=$width '
            '(was $previous, now $columns)',
      );
      previous = columns;
    }
  });

  testWidgets('the single threshold decides 4 columns vs 2, precisely',
      (tester) async {
    // With 4 children and a gap of AppTokens.md (16), 4 columns lands
    // exactly on StatTile.compactBelow (200) at an available width of 848:
    // (848 - 3*16) / 4 == 200. This is the only thing standing between 2
    // and 4 columns now that minTileWidth is gone, so it must be pinned by
    // a test rather than left free to drift.
    await pumpAt(tester, 849);
    expect(columnsOf(tester), 4, reason: 'just above the threshold');

    await pumpAt(tester, 847);
    expect(columnsOf(tester), 2, reason: 'just below the threshold');
  });

  testWidgets(
      'AsyncStatTile lays out at the grid-chosen step, both normal and '
      'compact', (tester) async {
    // The whole reason the step is published through the element tree
    // rather than copied onto StatTile's constructor: AsyncStatTile is not
    // a StatTile and has no compact field to copy onto, but it does render
    // a StatTile as a genuine descendant, which is what should let it pick
    // up the step this grid publishes.
    Widget grid() => StatTileGrid(children: [
          for (var i = 0; i < 4; i++)
            AsyncStatTile<int>(
              label: 'Async $i',
              value: AsyncValue.data(i),
              format: (n) => '$n',
              icon: Icons.circle,
              accent: AppTokens.accents[i],
            ),
        ]);

    Future<double> padAt(double width) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: grid())),
      ));
      await tester.pump();
      final padding = tester
          .widgetList<Padding>(find.byKey(const Key('statTilePadding')))
          .first;
      return (padding.padding as EdgeInsets).left;
    }

    // 1400px: 4 across, the normal step (padding 22).
    expect(await padAt(1400), 22);

    // 360px: 2 across, the compact step (padding 14).
    expect(await padAt(360), 14);
  });

  testWidgets(
      'a StatTile and an AsyncStatTile in the same grid share one height',
      (tester) async {
    // The combination the dashboards will actually use: not every tile is
    // stream-backed (a static "Not scheduled" tile, say), but most are, and
    // they sit in the same row. Both must land at the same height whatever
    // their internal wrapping looks like.
    final grid = StatTileGrid(children: [
      const StatTile(
        label: 'Plain tile',
        value: '1',
        caption: 'Has a caption',
        icon: Icons.check,
        accent: AppTokens.accentPine,
      ),
      AsyncStatTile<int>(
        label: 'Async tile',
        value: const AsyncValue.data(2),
        format: (n) => '$n',
        icon: Icons.check,
        accent: AppTokens.accentSeal,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: grid)),
    ));
    await tester.pump();

    double heightOf(String label) => tester
        .getSize(find.ancestor(
          of: find.text(label),
          matching: find.byType(StatTile),
        ))
        .height;

    expect(heightOf('Async tile'), heightOf('Plain tile'));
  });
}
