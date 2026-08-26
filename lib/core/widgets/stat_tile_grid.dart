import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';

/// The row of figures at the top of every dashboard.
///
/// Four across on a desktop, two-by-two on a tablet or a split window, and
/// still two-by-two on a phone. It never collapses to a single column at
/// any width a real device presents, and never stretches into the wide flat
/// strips that four equal columns produce on a large monitor.
///
/// Flutter has no `auto-fit`/`minmax`, so the column count is computed from
/// the available width and handed to a fixed-count grid. There are only two
/// candidate counts -- `children.length` and `2` -- rather than a continuous
/// range: this is deliberate, not a simplification. A single threshold
/// (`StatTile.compactBelow`) decides between them, which makes the column
/// count monotonic in width by construction, and restricting the candidates
/// to those two means four tiles can never split 3-then-1, with a lonely
/// tile stranded on its own row. An earlier version derived a raw count
/// from one rule and then vetoed it with a second, unrelated rule; the two
/// rules disagreed over a range of widths and the column count visibly
/// flickered (3 -> 2 -> 4) as a window was resized through it. One rule,
/// two candidates, removes that by construction.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.children});

  final List<Widget> children;

  static const double gap = AppTokens.md;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTokens.measureWide),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            // Take every tile across if each one would clear StatTile's own
            // compact threshold at that width; otherwise fall back to two.
            // Never fewer than two: a single column of tall cards is the
            // layout this widget exists to prevent.
            final full = children.length;
            final fullTileWidth = (available - (full - 1) * gap) / full;
            final columns =
                fullTileWidth >= StatTile.compactBelow ? full : 2;

            final rows = <Widget>[];
            for (var i = 0; i < children.length; i += columns) {
              final slice = children.skip(i).take(columns).toList();
              // Deliberately no crossAxisAlignment.stretch here (and no
              // IntrinsicHeight to fake one): every dashboard hosts this
              // widget inside a SingleChildScrollView, which hands the
              // Column unbounded height, and StatTile's own build method
              // uses a LayoutBuilder internally -- a combination that makes
              // both stretch (infinite height) and IntrinsicHeight
              // (LayoutBuilder cannot report intrinsic dimensions) crash
              // layout. Row's default cross-axis alignment (centre) is
              // enough regardless: StatTile now has a fixed height per
              // step rather than a minimum, so every tile in a row is
              // identical in height by construction, not by coincidence
              // of matching content.
              rows.add(Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: gap),
                    // Empty slots keep the last row's tiles the same width
                    // as every other row's, rather than letting a lone
                    // trailing tile expand to fill the line.
                    Expanded(
                      child: j < slice.length ? slice[j] : const SizedBox(),
                    ),
                  ],
                ],
              ));
              if (i + columns < children.length) {
                rows.add(const SizedBox(height: gap));
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            );
          },
        ),
      ),
    );
  }
}
