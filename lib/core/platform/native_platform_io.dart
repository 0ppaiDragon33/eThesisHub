import 'dart:io' show Platform;

/// True on a real Android or iOS build. On the desktop and in `flutter test`
/// (which runs on the host OS, not an emulated target) this is false, which
/// is what lets the widget tests see the desktop back-arrow behaviour without
/// any per-test platform override.
bool get isNativeMobile => Platform.isAndroid || Platform.isIOS;
