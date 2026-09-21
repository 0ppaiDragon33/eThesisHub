import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Guards the app's exit behind a second back within [window].
///
/// On a phone the shell hides its back arrow and leans on the OS back gesture
/// (Android's edge-swipe). At a top-level destination there is nothing left to
/// pop, so a stray swipe would either jump to a previously-visited screen or
/// drop the reader out of the app outright — losing where they were with no
/// warning. When [enabled], the first back is caught and answered with a
/// toast; only a second back inside [window] actually leaves.
///
/// [enabled] is set to false for a screen pushed on top of a destination, so
/// the OS back still pops that screen in one gesture as expected, and on web
/// and desktop, where there is no app to close and a visible back arrow does
/// the job instead.
///
/// Uses [BackButtonListener], not a bare [PopScope]: the app's shell is a
/// go_router `ShellRoute`, so a `PopScope` placed in the shell builder
/// registers on the ROOT route, and at a top-level destination go_router asks
/// the (single-page) nested navigator to pop, finds it cannot, and exits
/// WITHOUT ever consulting that root PopScope — the app closed on the first
/// swipe. `BackButtonListener` registers with the router's back-button
/// dispatcher and is consulted before go_router pops anything, so it actually
/// catches the gesture. It needs a `Router` ancestor (the app's
/// `MaterialApp.router` supplies one); mounting it only when [enabled] keeps
/// it off the disabled paths entirely.
class DoubleBackToExit extends StatefulWidget {
  const DoubleBackToExit({
    super.key,
    required this.enabled,
    required this.child,
    this.onExit,
    this.window = const Duration(seconds: 2),
    this.message = 'Swipe again to close the app',
  });

  final bool enabled;
  final Widget child;

  /// What a confirmed exit does. Defaults to [SystemNavigator.pop], which asks
  /// Android to move the task to the background exactly as the Home button
  /// would. Injectable so a test can observe the exit without killing itself.
  final VoidCallback? onExit;

  /// How long the first back stays "armed" for a confirming second one.
  final Duration window;

  /// The one line the toast shows on the first back.
  final String message;

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _armedAt;

  /// Returns true to swallow the back event so go_router never acts on it.
  Future<bool> _onBack() async {
    final now = DateTime.now();
    if (_armedAt != null && now.difference(_armedAt!) <= widget.window) {
      (widget.onExit ?? () => SystemNavigator.pop())();
      return true;
    }
    _armedAt = now;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.message),
          duration: widget.window,
          behavior: SnackBarBehavior.floating,
        ),
      );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Disabled (a deep screen, or web/desktop): stay out of the way entirely
    // so the OS back pops or exits exactly as it did before.
    if (!widget.enabled) return widget.child;
    return BackButtonListener(
      onBackButtonPressed: _onBack,
      child: widget.child,
    );
  }
}
