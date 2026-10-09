import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/success_splash.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Set by the sign-in screen when someone signs in, read once by the
/// signed-in shell to show the welcome.
///
/// A flag rather than something the sign-in screen shows itself: the router
/// replaces that screen the moment sign-in succeeds, so anything it drew
/// afterwards would be gone. Opening the app with a session already saved
/// never sets it, so there is no welcome on every launch.
final welcomePendingProvider = StateProvider<bool>((ref) => false);

/// How long the welcome stays before fading out.
const welcomeHold = Duration(milliseconds: 1400);

/// "Welcome back, Karl", the first word of a full name.
String welcomeTitle(String? fullName) {
  final first = (fullName ?? '').trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? 'Welcome back' : 'Welcome back, $first';
}

/// Lays the welcome over [child] (the signed-in app) right after sign-in,
/// then fades it out. Draws only [child] otherwise.
class WelcomeOverlay extends ConsumerStatefulWidget {
  const WelcomeOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WelcomeOverlay> createState() => _WelcomeOverlayState();
}

class _WelcomeOverlayState extends ConsumerState<WelcomeOverlay> {
  /// Visible (fading in or held).
  bool _showing = false;

  /// In the tree: true from the start until the fade-out has finished.
  bool _present = false;

  static const _fade = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    if (ref.read(welcomePendingProvider)) _start();
  }

  void _start() {
    _showing = true;
    _present = true;
    // Cleared straight away, so it shows once per sign-in however often the
    // shell rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(welcomePendingProvider.notifier).state = false;
    });
    Future<void>.delayed(welcomeHold, () {
      if (!mounted) return;
      setState(() => _showing = false);
      Future<void>.delayed(_fade, () {
        if (mounted && !_showing) setState(() => _present = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // A sign-in that lands while the shell is already up (rare: after a
    // sign-out and back in without the shell closing).
    ref.listen<bool>(welcomePendingProvider, (_, pending) {
      if (pending && !_showing) setState(_start);
    });
    final name = ref.watch(currentUserProvider).valueOrNull?.fullName;

    return Stack(
      children: [
        widget.child,
        if (_present)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_showing,
              child: AnimatedOpacity(
                opacity: _showing ? 1 : 0,
                duration: _fade,
                child: SuccessSplash(
                  key: const Key('welcomeSplash'),
                  title: welcomeTitle(name),
                  subtitle: 'Signed in to your eThesisHub account',
                  status: 'Signed in successfully!',
                  detail: 'Redirecting to your dashboard…',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
