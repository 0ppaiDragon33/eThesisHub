/// The web stub: `dart:io` does not exist on the web, and a browser is never
/// a "native mobile" target anyway — the visible back arrow stays, since a
/// browser has no in-app system back gesture.
bool get isNativeMobile => false;
