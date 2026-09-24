import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/widgets/confirm.dart';

void main() {
  Future<bool?> run(WidgetTester tester,
      {required Future<void> Function(WidgetTester) act}) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await confirmAction(
                context,
                title: 'Sign out?',
                message: 'You will need your account to sign back in.',
                confirmLabel: 'Sign out',
                cancelLabel: 'Stay',
                confirmKey: const Key('go'),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act(tester);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('confirming returns true', (tester) async {
    final r = await run(tester,
        act: (t) => t.tap(find.byKey(const Key('go'))));
    expect(r, isTrue);
  });

  testWidgets('cancelling returns false', (tester) async {
    final r = await run(tester, act: (t) => t.tap(find.text('Stay')));
    expect(r, isFalse);
  });

  testWidgets('dismissing by tapping outside counts as no', (tester) async {
    // A barrier tap must never be read as consent to a destructive action.
    final r = await run(tester,
        act: (t) => t.tapAt(const Offset(10, 10)));
    expect(r, isFalse);
  });
}
