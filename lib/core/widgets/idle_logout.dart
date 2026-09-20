import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';

/// How long the app sits untouched before it signs the reader out. Long
/// enough not to interrupt real work — reading a manuscript, deliberating a
/// grade — short enough that a thesis desk left open on a shared machine does
/// not stay open all afternoon.
const Duration kIdleTimeout = Duration(minutes: 20);

/// Signs a signed-in reader out after [timeout] of no pointer activity.
///
/// Wraps the whole app (below the router) so any tap, drag or scroll anywhere
/// resets the clock. Only acts while signed in: on the login screen the timer
/// still runs but its expiry is a no-op, and activity there simply re-arms it
/// against the next session.
class IdleLogout extends ConsumerStatefulWidget {
  const IdleLogout({
    super.key,
    required this.child,
    this.timeout = kIdleTimeout,
    this.messengerKey,
  });

  final Widget child;
  final Duration timeout;

  /// Used to tell the reader why they landed back on the login screen. The
  /// app owns the key and shares it with [MaterialApp.router]; a test may
  /// leave it null.
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  @override
  ConsumerState<IdleLogout> createState() => _IdleLogoutState();
}

class _IdleLogoutState extends ConsumerState<IdleLogout> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _onIdle);
  }

  Future<void> _onIdle() async {
    if (!mounted) return;
    final signedIn = ref.read(authStateProvider).valueOrNull != null;
    if (!signedIn) {
      // Nothing to sign out of; keep watching for the next session.
      _arm();
      return;
    }
    try {
      await ref.read(authServiceProvider).signOut();
      widget.messengerKey?.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Signed out after a period of inactivity.'),
        ),
      );
    } catch (_) {
      // The router redirect still sends them to login; a failed snackbar or
      // sign-out call must not throw out of a timer.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read: it keeps the auth stream alive so the timer callback
    // reads a settled value rather than a lazy AsyncLoading.
    ref.watch(authStateProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _arm(),
      onPointerMove: (_) => _arm(),
      onPointerSignal: (_) => _arm(),
      child: widget.child,
    );
  }
}
