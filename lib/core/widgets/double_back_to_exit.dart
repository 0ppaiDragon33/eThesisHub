import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Guards the app's exit behind a second back within [window].
///
/// On a phone the shell hides its back arrow and leans on the OS back gesture
/// (Android's edge-swipe). Left alone, a single swipe at a top-level
/// destination drops the reader out of the app; a swipe on a pushed screen
/// should still pop it. When [enabled], this catches the back: it pops a
/// pushed (deep) screen through go_router, and at a top-level destination it
/// warns with a toast and only leaves on a second back inside [window].
///
/// It listens on BOTH back-dispatch paths, because which one Android uses
/// depends on the device and build:
///   * [PopScope] — the framework's predictive-back / navigator path.
///   * [BackButtonListener] — the legacy back-button dispatcher path.
/// A single physical back fires only one of them; a short dedupe collapses
/// the rare case where both arrive. A bare [PopScope] in the shell builder was
/// not enough on its own: the shell is a go_router `ShellRoute`, so at a
/// top-level destination go_router asks the single-page nested navigator to
/// pop and, finding it cannot, closed the app before that PopScope was
/// consulted — hence also driving the pop through go_router here.
///
/// Both listeners need a `Router` ancestor (the app's `MaterialApp.router`
/// supplies one) and are mounted only when [enabled], so a disabled screen —
/// a deep screen on web, or desktop — behaves exactly as it did before.
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
  /// Android to move the task to the background as the Home button would.
  /// Injectable so a test can observe the exit without killing itself.
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
  DateTime? _lastEvent;

  /// Handles one back gesture. Returns true when it fully handled it (a pushed
  /// screen was popped, or the exit was armed/confirmed) so the legacy
  /// listener can report the event consumed.
  bool _handleBack() {
    final now = DateTime.now();

    // One physical back can reach both listeners within a frame; collapse
    // those. 100ms is far below any human double-tap, so a real second back
    // is never swallowed.
    if (_lastEvent != null &&
        now.difference(_lastEvent!) < const Duration(milliseconds: 100)) {
      return true;
    }
    _lastEvent = now;

    // A pushed screen pops in one gesture — route it through go_router so the
    // nested navigator actually pops rather than the app exiting.
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return true;
    }

    // Top-level destination: warn, then exit on a confirming second back.
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
    if (!widget.enabled) return widget.child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: BackButtonListener(
        onBackButtonPressed: () async => _handleBack(),
        child: widget.child,
      ),
    );
  }
}
