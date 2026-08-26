import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// One figure on a dashboard: a label, a number, and a coloured badge.
///
/// The proportions are load-bearing rather than decorative. Label and badge
/// are pushed to opposite edges, the value sits below a fixed gap, and the
/// padding is generous enough that the card reads as a card rather than as
/// a table row. Four tiles that ignore this look like flat strips stretched
/// across a monitor, which is precisely the complaint this widget was built
/// to answer.
///
/// The card's height is a MINIMUM (148 normal / 116 compact), not fixed: a
/// fixed height was tried and rejected, because worst-case content (a label
/// or caption that wraps to its full two lines) needs roughly 172px, and no
/// single constant can both fit that and avoid inflating every shorter tile
/// to match. [label] and [caption] are still clamped to two lines with an
/// ellipsis -- that only bounds them horizontally, stopping an overlong
/// string from pushing the card wider or wrapping past two lines, not
/// vertically. Making a row of tiles share one height despite that
/// variability is the tile grid's job, not this widget's: it wraps each
/// row in `IntrinsicHeight`, which sizes every tile in the row to the
/// tallest one's real content, with this minimum as the floor. A lone
/// `StatTile` outside a grid (as in this file's own tests) still sizes to
/// its own content, which is why the minimum exists at all.
///
/// The badge colour comes from [AppTokens.accents] and is fixed by the
/// tile's position on its dashboard. It must NEVER be derived from the
/// status of whatever is being counted: accents identify, they do not judge,
/// and a badge that turns green on approval would collide with the meaning
/// palette used by chips and buttons a few pixels away.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.unit,
    this.caption,
    this.progress,
    this.onTap,
    this.valueIsText = false,
    this.compact,
  });

  final String label;

  /// A `String`, not a number: several tiles show text ("Not scheduled",
  /// a supervisor's name). Callers that pass prose set [valueIsText] so the
  /// size drops — the widget does not try to guess from the content.
  final String value;
  final String? unit;
  final String? caption;

  /// 0..1. When present, a slim bar replaces [caption].
  ///
  /// This is the honest substitute for the reference design's "+8% this
  /// month". A delta needs a stored snapshot of the previous value and
  /// nothing in this system keeps one, so where a genuine ratio exists it
  /// fills that space and where none exists the space stays empty.
  final double? progress;

  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool valueIsText;

  /// When a caller already knows the step -- the tile grid does, because
  /// it has already computed the tile's width while choosing the column
  /// count -- it can pass that here, and this widget skips its own
  /// `LayoutBuilder` entirely, building directly at the given step.
  /// `LayoutBuilder` cannot report intrinsic dimensions, which is what
  /// stops a grid from sizing a row with `IntrinsicHeight` when every tile
  /// decides its own step independently; a tile that is TOLD its step
  /// removes that obstacle. Left `null` (the default), the tile falls back
  /// to measuring its own width via `LayoutBuilder`, exactly as before -- a
  /// standalone tile (as in this file's tests, pumped directly at a fixed
  /// width) still works with no caller changes.
  final bool? compact;

  /// Below this width the tile steps down a size. Keyed off the tile's own
  /// width rather than the screen's, so a tile placed in a narrow column on
  /// a wide display behaves correctly. Only consulted when [compact] is not
  /// supplied by the caller.
  static const double compactBelow = 200;

  @override
  Widget build(BuildContext context) {
    if (compact != null) return _build(context, compact!);
    return LayoutBuilder(
      builder: (context, constraints) {
        return _build(context, constraints.maxWidth < compactBelow);
      },
    );
  }

  Widget _build(BuildContext context, bool compact) {
    final scheme = Theme.of(context).colorScheme;

    final pad = compact ? 14.0 : 22.0;
    final badge = compact ? 28.0 : 38.0;
    final minHeight = compact ? 116.0 : 148.0;
    final valueSize =
        valueIsText ? (compact ? 15.0 : 19.0) : (compact ? 24.0 : 31.0);

    final card = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: AppTokens.rule),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTokens.ink.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        key: const Key('statTilePadding'),
        padding: EdgeInsets.all(pad),
        child: Column(
          // The Container above sets a minimum, not a fixed height, so
          // this Column's main axis is unbounded here -- an Expanded or
          // Spacer would throw. mainAxisSize.min is what lets the card
          // grow past the minimum for tall content (a wrapped label or
          // caption) instead of overflowing. Sharing one height across a
          // row of tiles is the tile grid's job (IntrinsicHeight + this
          // minimum as the floor), not this widget's -- do not "fix" this
          // back to a Spacer.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 11.5 : 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  ),
                  child: Icon(
                    icon,
                    size: compact ? 15 : 19,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 12 : 18),
            _value(context, valueSize, compact),
            if (progress != null)
              _bar(context, compact)
            else if (caption != null) ...[
              SizedBox(height: compact ? 5 : 7),
              Text(
                caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 12,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: card,
    );
  }

  Widget _value(BuildContext context, double size, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.serif,
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.4,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: AppTokens.xs),
          Text(
            unit!,
            style: TextStyle(
              fontFamily: AppTheme.serif,
              fontSize: compact ? 13 : 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bar(BuildContext context, bool compact) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 11),
      child: ClipRRect(
        key: const Key('statTileBar'),
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress!.clamp(0.0, 1.0),
          minHeight: 5,
          backgroundColor: AppTokens.rule,
          valueColor: AlwaysStoppedAnimation<Color>(accent),
        ),
      ),
    );
  }
}

/// A [StatTile] whose value is still arriving.
///
/// A separate widget rather than a named constructor because the async form
/// must be generic over the streamed value and a named constructor cannot
/// introduce a type parameter.
///
/// While loading it renders a skeleton bar. It must never render `0`: this
/// project has four times shipped a screen where a loading count and a real
/// count of nothing were indistinguishable, which tells the reader their
/// queue is empty when it may be full.
class AsyncStatTile<T> extends StatelessWidget {
  const AsyncStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    required this.icon,
    required this.accent,
    this.unit,
    this.caption,
    this.progress,
    this.onTap,
    this.valueIsText = false,
  });

  final String label;
  final AsyncValue<T> value;
  final String Function(T) format;
  final String? unit;
  final String? Function(T)? caption;
  final double? Function(T)? progress;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool valueIsText;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => _Skeleton(
        label: label,
        icon: icon,
        accent: accent,
      ),
      // An em dash, not a zero. The read failed; the count is unknown, and
      // saying "0" would be a claim the app cannot support.
      error: (_, _) => StatTile(
        label: label,
        value: '—',
        icon: icon,
        accent: accent,
        caption: 'Could not load',
      ),
      data: (v) => StatTile(
        label: label,
        value: format(v),
        unit: unit,
        caption: caption?.call(v),
        progress: progress?.call(v),
        icon: icon,
        accent: accent,
        onTap: onTap,
        valueIsText: valueIsText,
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      key: const Key('statTileSkeleton'),
      label: label,
      value: ' ',
      icon: icon,
      accent: accent,
      progress: null,
      caption: 'Loading…',
    );
  }
}
