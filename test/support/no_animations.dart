import 'package:flutter_test/flutter_test.dart';

/// Disables animations for the current test, the way a reduce-motion user's
/// device does.
///
/// The shell's loading states are skeletons: a `FadeIn` (which schedules a
/// one-shot delay `Timer`) wrapping a `Shimmer` (which `repeat()`s a ticker
/// forever). A test that pumps a loading state and ends leaves that timer
/// pending and that ticker active, and the framework rightly fails the test
/// for it — the widgets are behaving correctly, the harness simply never let
/// them finish.
///
/// Both widgets honour `MediaQuery.disableAnimations`: `FadeIn` jumps
/// straight to its end state with no timer, and `Shimmer` never starts its
/// ticker. Calling this before `pumpWidget` therefore lets a loading-state
/// assertion run and tear down cleanly, while still exercising the real
/// loading widget rather than a stand-in.
void disableAnimationsForTest(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}
