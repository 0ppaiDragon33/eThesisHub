import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/widgets/double_back_to_exit.dart';

void main() {
  Widget host({
    required bool enabled,
    required VoidCallback onExit,
    Duration window = const Duration(seconds: 2),
  }) =>
      MaterialApp(
        home: Scaffold(
          body: DoubleBackToExit(
            enabled: enabled,
            onExit: onExit,
            window: window,
            child: const Center(child: Text('home')),
          ),
        ),
      );

  testWidgets('the first back warns and does not exit; a second within the '
      'window exits', (tester) async {
    var exits = 0;
    await tester.pumpWidget(host(enabled: true, onExit: () => exits++));

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

  testWidgets('when disabled the back pops normally and the guard never fires',
      (tester) async {
    var exits = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DoubleBackToExit(
                enabled: false,
                onExit: () => exits++,
                child: const Scaffold(body: Center(child: Text('pushed'))),
              ),
            )),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('pushed'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('pushed'), findsNothing,
        reason: 'a disabled guard lets the pop through in one gesture');
    expect(exits, 0);
  });
}
