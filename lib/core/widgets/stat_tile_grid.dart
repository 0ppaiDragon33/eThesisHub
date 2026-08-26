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
///
/// This grid takes `List<StatTile>` rather than `List<Widget>` because it
/// tells every tile its step (compact or not) rather than letting each tile
/// guess from its own width via `LayoutBuilder`. That is what lets a row be
/// wrapped in `IntrinsicHeight` -- `LayoutBuilder` cannot report intrinsic
/// dimensions, so a `StatTile` measuring itself would make `IntrinsicHeight`
/// throw. This grid already computes the tile width while choosing the
/// column count, so it hands `StatTile` the answer instead.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.children});

  final List<StatTile> children;

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
            final columns = fullTileWidth >= StatTile.compactBelow ? full : 2;
            final tileWidth = (available - (columns - 1) * gap) / columns;
            final compact = tileWidth < StatTile.compactBelow;

            final rows = <Widget>[];
            for (var i = 0; i < children.length; i += columns) {
              final slice = children.skip(i).take(columns).toList();
              // Every tile in the row is told its step (see the class doc),
              // so none of them runs its own LayoutBuilder, which is what
              // makes IntrinsicHeight safe here: it sizes the row to the
              // tallest tile's real content, with StatTile's minHeight as
              // the floor, rather than every tile guessing independently
              // and disagreeing.
              rows.add(IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) const SizedBox(width: gap),
                      // Empty slots keep the last row's tiles the same
                      // width as every other row's, rather than letting a
                      // lone trailing tile expand to fill the line.
                      Expanded(
                        child: j < slice.length
                            ? _withStep(slice[j], compact)
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
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

  /// Rebuilds [tile] with [compact] forced, rather than left for the tile
  /// to work out from its own width. A plain field copy: every other
  /// property of [StatTile] is public and unrelated to layout.
  static StatTile _withStep(StatTile tile, bool compact) {
    return StatTile(
      key: tile.key,
      label: tile.label,
      value: tile.value,
      icon: tile.icon,
      accent: tile.accent,
      unit: tile.unit,
      caption: tile.caption,
      progress: tile.progress,
      onTap: tile.onTap,
      valueIsText: tile.valueIsText,
      compact: compact,
    );
  }
}
