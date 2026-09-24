import 'dart:async';

import 'package:flutter/material.dart';

/// Swaps its child with a short fade, a small horizontal slide and a
/// smooth height change whenever [value] changes.
///
/// Used where one control changes what a region means (the faculty
/// Adviser / Panelist switch), so the reader sees the region change rather
/// than content silently replacing itself. [forward] picks the slide
/// direction: true moves the new content in from the right.
class ModeSwap<T> extends StatelessWidget {
  const ModeSwap({
    super.key,
    required this.value,
    required this.child,
    this.forward = true,
    this.duration = const Duration(milliseconds: 280),
  });

  final T value;
  final Widget child;
  final bool forward;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Respect the platform's reduce-motion setting.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final d = reduce ? Duration.zero : duration;
    final dx = forward ? 0.04 : -0.04;

    return AnimatedSize(
      duration: d,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: d,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // Stack the outgoing child behind the incoming one, top-aligned,
        // so the two never push each other around mid-swap.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            for (final p in previous)
              Positioned(left: 0, right: 0, top: 0, child: p),
            ?current,
          ],
        ),
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey<T>(value);
          final offset = Tween<Offset>(
            begin: Offset(incoming ? dx : -dx, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: KeyedSubtree(key: ValueKey<T>(value), child: child),
      ),
    );
  }
}

/// Sweeps a soft highlight across [child] while content loads.
///
/// Paints only where the child paints (skeleton bars, blocks), so the
/// highlight follows the shape of what is coming. Holds still when the
/// platform asks for reduced motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlight = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.65);

    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 2 - 0.5; // sweep from off-left to off-right
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              highlight,
              Colors.transparent,
            ],
            stops: [
              (t - 0.25).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.25).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// A rounded placeholder block for skeleton layouts.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 4,
    this.widthFactor,
  });

  final double? width;
  final double height;
  final double radius;

  /// A fraction of the available width, for text-line placeholders.
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (widthFactor == null) return box;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: box,
    );
  }
}

/// Fades and lifts its child in once, when it first appears — for content
/// that has just replaced a loading skeleton.
class FadeIn extends StatefulWidget {
  const FadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  bool _started = false;

  /// Held so it can be cancelled in [dispose]. A `Future.delayed` here would
  /// leave a pending timer to fire after the widget is gone — guarded only
  /// by `mounted`, and flagged by the test framework as a leak — so a
  /// cancellable [Timer] is used instead.
  Timer? _delayTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
