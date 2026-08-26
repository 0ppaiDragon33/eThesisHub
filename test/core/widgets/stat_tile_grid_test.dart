import 'package:flutter/material.dart';
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
    // long flat strips. The row caps rather than smearing.
    await pumpAt(tester, 2400);
    final tile = tester.getSize(find.ancestor(
      of: find.text('Tile 0'),
      matching: find.byType(StatTile),
    ));
    expect(tile.width, lessThan(340));
  });
}
