import 'dart:async';

import 'package:flutter/material.dart';

/// A [ChangeNotifier] that listens to a stream and notifies listeners on each emission.
///
/// Used to drive [GoRouter] refresh when async providers (like [authStateProvider])
/// emit new values. Disposes the stream subscription automatically.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
