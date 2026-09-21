import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/double_back_to_exit.dart';

void main() {
  // A real Router, because BackButtonListener registers with the router's
  // back-button dispatcher — exactly what makes it work inside the app's
  // ShellRoute where a bare PopScope did not.
  Widget host({
    required bool enabled,
    required VoidCallback onExit,
    Duration window = const Duration(seconds: 2),
  }) {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: DoubleBackToExit(
            enabled: enabled,
            onExit: onExit,
            window: window,
            child: const Center(child: Text('home')),
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('the first back warns and does not exit; a second within the '
      'window exits', (tester) async {
    var exits = 0;
    await tester.pumpWidget(host(enabled: true, onExit: () => exits++));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Swipe again to close the app'), findsOneWidget);
    expect(exits, 0, reason: 'one back only warns');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 1, reason: 'the confirming second back leaves the app');
  });

  testWidgets('a back after the window lapses re-arms rather than exiting',
      (tester) async {
    var exits = 0;
    await tester.pumpWidget(host(
      enabled: true,
      onExit: () => exits++,
      window: const Duration(milliseconds: 200),
    ));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);

    // Real time, because the widget arms itself off DateTime.now().
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)));

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0,
        reason: 'the first back had expired, so this one only re-arms');
    expect(find.text('Swipe again to close the app'), findsOneWidget);
  });

  testWidgets('when disabled the back is not intercepted and pops normally',
      (tester) async {
    var exits = 0;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => context.push('/deep'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/deep',
        builder: (_, _) => DoubleBackToExit(
          enabled: false,
          onExit: () => exits++,
          child: const Scaffold(body: Center(child: Text('pushed'))),
        ),
      ),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('pushed'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('pushed'), findsNothing,
        reason: 'a disabled guard lets the pushed screen pop in one gesture');
    expect(exits, 0);
  });
}
