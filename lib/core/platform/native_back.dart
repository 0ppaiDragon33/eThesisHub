import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// The channel `MainActivity` uses to ask Dart to pop a pushed screen before
/// it decides whether to double-back-to-exit. See
/// `android/app/src/main/kotlin/.../MainActivity.kt`.
///
/// The Android back gesture is owned in native code because go_router's
/// `ShellRoute` reports "nothing to pop" to Android at a top-level
/// destination, so a Dart-side `PopScope`/`BackButtonListener` is never
/// consulted — the activity finishes first. Native intercepts the gesture and
/// calls here so a deep screen still pops through go_router.
const MethodChannel nativeNavigationChannel = MethodChannel('app/navigation');

/// The dashboard: the one page where back offers to close the app.
const String nativeBackHome = '/overview';

/// Pages outside the signed-in shell. Back there offers to close the app
/// too, since there is no dashboard to go to.
const Set<String> _signedOutPaths = {
  '/login',
  '/register',
  '/verify-email',
  '/deactivated',
  '/no-profile',
};

/// Answers the native back request (the gesture and the back button alike):
/// - a pushed screen pops through [router]; answers true.
/// - any other page in the app goes to the dashboard; answers true.
/// - on the dashboard, or signed out, answers false, and the native side
///   warns once and closes the app on a second back.
///
/// Returns null for any other method.
Future<Object?> handleNativeBack(GoRouter router, MethodCall call) async {
  if (call.method != 'popRoute') return null;
  if (router.canPop()) {
    router.pop();
    return true;
  }
  final path = router.routerDelegate.currentConfiguration.uri.path;
  if (path != nativeBackHome && !_signedOutPaths.contains(path)) {
    router.go(nativeBackHome);
    return true;
  }
  return false;
}

/// Wires [handleNativeBack] onto [channel]. Called once at startup.
void registerNativeBackHandler(
  GoRouter router, {
  MethodChannel channel = nativeNavigationChannel,
}) {
  channel.setMethodCallHandler((call) => handleNativeBack(router, call));
}
