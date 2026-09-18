import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// One figure in a [MetricStrip].
///
/// Async on purpose: a figure still loading shows a quiet bar, never a
/// false zero, and a failed read shows a dash with the reason in a tooltip.
class Metric<T> extends StatelessWidget {
  const Metric({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    this.caption,
    this.onTap,
    this.highlight,
    this.textValue = false,
  });

  final String label;
  final AsyncValue<T> value;
  final String Function(T) format;
  final String? Function(T)? caption;
  final VoidCallback? onTap;

  /// When it returns true the figure is drawn in the act colour — used for
  /// "this is waiting on you" counts that are above zero.
  final bool Function(T)? highlight;

  /// A word or date rather than a count; set smaller.
  final bool textValue;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;

    final figureStyle = TextStyle(
      fontFamily: AppTheme.serif,
      fontSize: textValue ? 19 : 34,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: textValue ? -0.2 : -0.8,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: p.text,
    );

    final Widget figure = value.when(
      loading: () => Padding(
        key: const Key('metricLoading'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Shimmer(
          child: SkeletonBox(
            width: textValue ? 90 : 52,
            height: textValue ? 14 : 24,
            radius: 6,
          ),
        ),
      ),
      error: (e, _) => Tooltip(
        message: 'Could not load this figure',
        child: Text('—', style: figureStyle.copyWith(color: p.muted)),
      ),
      data: (v) => FadeIn(
        child: Text(
        format(v),
        maxLines: textValue ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: (highlight?.call(v) ?? false)
            ? figureStyle.copyWith(color: p.seal)
            : figureStyle,
      ),
      ),
    );

    final cap = value.valueOrNull == null
        ? null
        : caption?.call(value.valueOrNull as T);

    final body = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg - 4, vertical: AppTokens.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: p.muted)),
              ),
              if (onTap != null)
                Icon(Icons.north_east_rounded, size: 14, color: p.muted),
            ],
          ),
          const SizedBox(height: AppTokens.sm),
          figure,
          if (cap != null) ...[
            const SizedBox(height: AppTokens.xs),
            Text(cap,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall),
          ],
        ],
      ),
    );

    if (onTap == null) return Semantics(container: true, child: body);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}

/// A single band of figures divided by rules — one object, not four cards.
///
/// Four across when there is room, otherwise a two-by-two grid. The
/// decision is made once for the whole strip from its own width.
class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.metrics});

  final List<Widget> metrics;

  static const double _minCell = 170;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(AppTokens.radius + 2),
        border: Border.all(color: p.rule),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radius + 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final n = metrics.length;
            final across = constraints.maxWidth / n >= _minCell ? n : 2;
            final rows = <Widget>[];
            for (var i = 0; i < n; i += across) {
              final slice = metrics.skip(i).take(across).toList();
              if (i > 0) rows.add(Divider(height: 1, color: p.rule));
              rows.add(IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < across; j++) ...[
                      if (j > 0) VerticalDivider(width: 1, color: p.rule),
                      Expanded(
                        child: j < slice.length ? slice[j] : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ));
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

/// A proportional bar of counts — used for the college pipeline.
///
/// The bar is the at-a-glance shape; the legend under it carries every
/// number in words, so nothing depends on reading colour.
class SegmentBar extends StatelessWidget {
  const SegmentBar({super.key, required this.segments, this.onTap});

  final List<({String label, int count, Color color})> segments;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final total = segments.fold<int>(0, (a, s) => a + s.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: total == 0
                ? ColoredBox(color: p.rule)
                : Row(
                    children: [
                      for (final s in segments)
                        if (s.count > 0)
                          Expanded(
                            flex: s.count,
                            child: Container(
                              margin: const EdgeInsets.only(right: 2),
                              color: s.color,
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppTokens.md),
        Wrap(
          spacing: AppTokens.xs,
          runSpacing: AppTokens.xs,
          children: [
            for (var i = 0; i < segments.length; i++)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onTap == null ? null : () => onTap!(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.sm, vertical: AppTokens.xs),
                  // Bounded so a single legend item can never be wider than a
                  // narrow panel (the "chart given no space" case) — the label
                  // ellipsizes rather than overflowing the row.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: segments[i].color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(segments[i].label,
                              style: text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${segments[i].count}',
                          style: text.labelMedium?.copyWith(
                            color: p.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
