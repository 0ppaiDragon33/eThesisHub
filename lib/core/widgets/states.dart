import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// Nothing here yet — and what to do about it.
///
/// An empty queue previously rendered as blank space, which reads as a
/// screen that failed to load. An empty screen is an invitation to act, so
/// this always says what would put something here, and offers the action
/// when there is one to offer.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg, vertical: AppTokens.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radius + 2),
        border: Border.all(color: p.rule),
        color: p.paper,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: p.seal.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: p.seal),
          ),
          const SizedBox(height: AppTokens.md),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppTokens.xs + 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              style: text.bodyMedium?.copyWith(color: p.muted),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppTokens.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Something went wrong — said plainly, with a way forward.
///
/// Errors do not apologise and are never vague about what happened. The one
/// case worth naming specifically is a permission denial, because on this
/// system that almost always means the account is not verified or does not
/// hold the role, and telling someone that is the difference between a
/// dead end and a next step.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.error,
  });

  final String message;
  final VoidCallback? onRetry;

  /// The underlying failure, shown as a short code beneath the message.
  ///
  /// There are no server-side logs on the Spark plan, so when something is
  /// refused in the field the only place the reason can surface is the
  /// screen. Without it a missing Firestore index and a dropped connection
  /// look identical, and the friendly copy actively misleads: "check your
  /// connection" sent someone hunting a network problem that did not exist.
  ///
  /// Kept to the code alone, never a stack trace or a raw exception string.
  final Object? error;

  /// Firestore's own codes, translated into what to actually do. Anything
  /// unrecognised falls through to the caller's message.
  static String? _hintFor(Object? error) {
    if (error is! FirebaseException) return null;
    return switch (error.code) {
      'failed-precondition' =>
        'This query needs a Firestore index that has not been created yet.',
      'permission-denied' =>
        'The security rules refused this read for your account.',
      'unavailable' => 'Could not reach Firestore.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.md, AppTokens.md, AppTokens.sm, AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.06),
        border: Border(left: BorderSide(color: scheme.error, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_gmailerrorred_rounded, size: 20, color: scheme.error),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message first, then hint: they answer different questions
                // and the caller's is the one that cannot be reconstructed.
                // The hint used to REPLACE the message, so every
                // permission-denied on a screen with four streams rendered
                // an identical box and there was no way to tell which read
                // had failed -- which is exactly the situation this project
                // hit in the field, with no server-side logs to fall back on.
                Text(message,
                    style: text.bodyMedium?.copyWith(color: scheme.error)),
                if (_hintFor(error) != null) ...[
                  const SizedBox(height: AppTokens.xs),
                  Text(_hintFor(error)!,
                      style: text.bodySmall?.copyWith(color: scheme.error)),
                ],
                if (error is FirebaseException) ...[
                  const SizedBox(height: AppTokens.xs),
                  // Selectable: with no server-side logs, this code is what a
                  // reader reads out or pastes to whoever can help, so it has
                  // to be copyable rather than just legible.
                  SelectableText(
                    '[${(error as FirebaseException).code}]',
                    key: const Key('errorCode'),
                    style: text.labelSmall?.copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// A loading state that holds its place rather than collapsing the layout.
///
/// The default form is three shimmering text lines with the label beneath,
/// for a region inside a page. [LoadingState.page] draws the rough shape of
/// a whole screen (header, figure strip, two columns of panels) for routes
/// that have nothing to show until their first read lands.
///
/// Both fade in after a short delay, so a read that resolves almost at
/// once never flashes a skeleton.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label}) : _page = false;

  const LoadingState.page({super.key, this.label}) : _page = true;

  final String? label;
  final bool _page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? null : 240,
        child: Semantics(
          label: label ?? 'Loading',
          liveRegion: true,
          child: FadeIn(
            delay: const Duration(milliseconds: 120),
            child: _page
                ? _PageSkeleton(label: label)
                : _LinesSkeleton(label: label),
          ),
        ),
      ),
    );
  }
}

class _LinesSkeleton extends StatelessWidget {
  const _LinesSkeleton({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBox(widthFactor: 0.9),
                SizedBox(height: AppTokens.sm + 2),
                SkeletonBox(widthFactor: 0.7),
                SizedBox(height: AppTokens.sm + 2),
                SkeletonBox(widthFactor: 0.45),
              ],
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: AppTokens.md - 4),
            _LoadingLabel(label: label!),
          ],
        ],
      ),
    );
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _PulseDots(),
        const SizedBox(width: AppTokens.sm),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Three dots that pulse in turn: a quieter "working" signal than a spinner.
class _PulseDots extends StatefulWidget {
  const _PulseDots();

  @override
  State<_PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<_PulseDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seal = Palette.of(context).seal;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Builder(builder: (context) {
                // Each dot peaks a third of a cycle after the one before.
                final phase = (_c.value - i / 3) % 1.0;
                final lift = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                return Opacity(
                  opacity: 0.3 + 0.7 * lift,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: seal, shape: BoxShape.circle),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// The rough shape of a screen: header, a figure band, and two columns of
/// panels (stacked on narrow widths).
class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    Widget panel({required double height, int lines = 3}) => Container(
          height: height,
          padding: const EdgeInsets.all(AppTokens.lg - 4),
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(AppTokens.radius + 2),
            border: Border.all(color: p.rule),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SkeletonBox(width: 140, height: 14),
              const SizedBox(height: AppTokens.lg - 4),
              for (var i = 0; i < lines; i++) ...[
                SkeletonBox(widthFactor: i.isEven ? 0.85 : 0.6),
                const SizedBox(height: AppTokens.sm + 2),
              ],
            ],
          ),
        );

    return Shimmer(
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 860;
        final primary = [panel(height: 220, lines: 5), panel(height: 180)];
        final secondary = [panel(height: 150, lines: 2), panel(height: 200)];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkeletonBox(width: 180, height: 12),
            const SizedBox(height: AppTokens.sm + 2),
            const SkeletonBox(width: 320, height: 30, radius: 6),
            const SizedBox(height: AppTokens.sm + 2),
            const SkeletonBox(widthFactor: 0.5, height: 12),
            const SizedBox(height: AppTokens.lg),
            Container(
              height: 104,
              decoration: BoxDecoration(
                color: p.paper,
                borderRadius: BorderRadius.circular(AppTokens.radius + 2),
                border: Border.all(color: p.rule),
              ),
              padding: const EdgeInsets.all(AppTokens.lg - 4),
              child: Row(
                children: [
                  for (var i = 0; i < (wide ? 4 : 2); i++) ...[
                    if (i > 0) const SizedBox(width: AppTokens.lg),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 90, height: 10),
                          SizedBox(height: AppTokens.md - 4),
                          SkeletonBox(width: 48, height: 30, radius: 6),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 8,
                    child: Column(children: [
                      primary[0],
                      const SizedBox(height: AppTokens.lg),
                      primary[1],
                    ]),
                  ),
                  const SizedBox(width: AppTokens.lg),
                  Expanded(
                    flex: 5,
                    child: Column(children: [
                      secondary[0],
                      const SizedBox(height: AppTokens.lg),
                      secondary[1],
                    ]),
                  ),
                ],
              )
            else
              for (final w in [...primary, ...secondary]) ...[
                w,
                const SizedBox(height: AppTokens.md),
              ],
            if (label != null) ...[
              const SizedBox(height: AppTokens.md),
              _LoadingLabel(label: label!),
            ],
          ],
        );
      }),
    );
  }
}
