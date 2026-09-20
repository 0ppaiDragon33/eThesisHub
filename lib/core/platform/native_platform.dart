// [isNativeMobile] resolved per platform: the `dart:io` implementation on
// Android/iOS/desktop, and a `false` stub on the web where `dart:io` does
// not exist. See the two implementation files for why this matters to the
// widget tests.
export 'native_platform_io.dart'
    if (dart.library.html) 'native_platform_web.dart';
