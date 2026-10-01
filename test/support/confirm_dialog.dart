import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps the confirming button of a `confirmAction` dialog, if one opened.
///
/// Decisive actions (accept, decline, submit, approve, schedule, ...) ask
/// "are you sure?" first. Tests that are about what the action DOES call
/// this right after tapping it. A tap the screen refuses before asking (a
/// missing reason, an unscored criterion) opens no dialog, so this does
/// nothing there and the test goes on to check the refusal.
Future<void> confirmIfAsked(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final confirm = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(FilledButton),
  );
  if (confirm.evaluate().isEmpty) return;
  await tester.tap(confirm.last);
  await tester.pump();
}
