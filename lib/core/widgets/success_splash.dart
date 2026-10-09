import 'package:flutter/material.dart';

/// A full-screen "it worked, carrying on" moment: a heading and a line under
/// it, then a check that pops in, a status line, what is happening next, and
/// three bouncing dots.
///
/// Used after signing in ("Welcome back … Signed in successfully!") and when
/// a faculty member switches between Adviser and Panelist view. Purely
/// visual; whoever shows it takes it away.
class SuccessSplash extends StatelessWidget {
  const SuccessSplash({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.detail,
  });

  /// "Welcome back", "Switching to Panelist View".
  final String title;
  final String subtitle;

  /// "Signed in successfully!", "Panelist View ready".
  final String status;

  /// "Redirecting to your dashboard…".
  final String detail;

  static const _done = Color(0xFF2F9E5B);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: const Key('splashTitle'),
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduceMotion ? 1 : 0.4, end: 1),
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutBack,
                          builder: (_, s, child) =>
                              Transform.scale(scale: s, child: child),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _done.withValues(alpha: 0.14),
                            ),
                            child: const Icon(
                              Icons.check_circle_outline_rounded,
                              color: _done,
                              size: 34,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detail,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _BouncingDots(
                          color: scheme.onSurface,
                          animate: !reduceMotion,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots rising one after another, like a "working on it" ellipsis.
class _BouncingDots extends StatefulWidget {
  const _BouncingDots({required this.color, required this.animate});

  final Color color;
  final bool animate;

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.translate(
                // Each dot lifts in turn, a third of a cycle apart.
                offset: Offset(0, -4 * _lift((_c.value - i / 3) % 1)),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Up and back down in the first half of the cycle, still in the second.
  static double _lift(double t) {
    if (t > 0.5) return 0;
    final x = t * 2;
    return 4 * x * (1 - x);
  }
}
