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
/// the available width and handed to a fixed-count grid. `minTileWidth`
/// drives that computation and the `.clamp(2, children.length)` below it is
/// the actual guarantee against a single column -- it holds regardless of
/// `minTileWidth`, by design. `minTileWidth` is still load-bearing: raise it
/// past what a mid-width screen can offer four roomy columns and the
/// tablet breakpoint (700px) buckles to three columns instead of two,
/// which is exactly as ugly as the single column this widget exists to
/// prevent. See the compact-threshold gate below for the other half of
/// that decision.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.children});

  final List<Widget> children;

  static const double minTileWidth = 150;
  static const double gap = AppTokens.md;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTokens.measureWide),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            // How many columns of at least minTileWidth fit, counting the
            // gaps between them. Never fewer than two: a single column of
            // tall cards is the layout this widget exists to prevent.
            var columns = ((available + gap) / (minTileWidth + gap)).floor();
            columns = columns.clamp(2, children.length);

            // The floor above only guarantees each tile clears the absolute
            // minimum -- at a 700px tablet width, four columns of 150px
            // technically fit (163px each), but that is StatTile's compact
            // step, which reads as cramped rather than roomy on a screen
            // that size. Stepping up past two columns is only worth it once
            // each tile would clear StatTile's own compact threshold;
            // otherwise two roomier columns beat more, cramped ones.
            if (columns > 2) {
              final tileWidth = (available - (columns - 1) * gap) / columns;
              if (tileWidth < StatTile.compactBelow) columns = 2;
            }

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
              // layout. Row's default cross-axis alignment centres children
              // instead, which is enough: every tile in a row shares the
              // same width via Expanded, so StatTile's own compact/regular
              // minHeight is already identical across the row.
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
