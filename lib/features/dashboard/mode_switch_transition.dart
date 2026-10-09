import 'package:flutter/material.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';

/// How long the switching screen stays up before it clears itself.
const modeSwitchHold = Duration(milliseconds: 1100);

/// The heading on the switching screen: "Switching to Panelist View".
String modeSwitchTitle(FacultyMode to) =>
    'Switching to ${to == FacultyMode.adviser ? 'Adviser' : 'Panelist'} View';

/// Shows a short full-screen "Switching to … View" moment while the
/// sidebar and pages change over to the other mode, then clears itself.
/// Purely visual: the mode has already changed when this appears.
Future<void> showModeSwitchTransition(BuildContext context, FacultyMode to) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: modeSwitchTitle(to),
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => _ModeSwitchScreen(to: to),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _ModeSwitchScreen extends StatefulWidget {
  const _ModeSwitchScreen({required this.to});

  final FacultyMode to;

  @override
  State<_ModeSwitchScreen> createState() => _ModeSwitchScreenState();
}

class _ModeSwitchScreenState extends State<_ModeSwitchScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(modeSwitchHold, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final adviser = widget.to == FacultyMode.adviser;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    const done = Color(0xFF2F9E5B);

    return Material(
      key: const Key('modeSwitchScreen'),
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
                    modeSwitchTitle(widget.to),
                    key: const Key('modeSwitchTitle'),
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    adviser
                        ? 'Your menu now shows the groups you advise.'
                        : 'Your menu now shows the panels you sit on.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        // The check pops in, as in the sign-in screen.
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
                              color: done.withValues(alpha: 0.14),
                            ),
                            child: const Icon(
                              Icons.check_circle_outline_rounded,
                              color: done,
                              size: 34,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${adviser ? 'Adviser' : 'Panelist'} View ready',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          adviser
                              ? 'Opening your advisees…'
                              : 'Opening your panels…',
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
