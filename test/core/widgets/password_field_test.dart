import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/widgets/password_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  bool obscured(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).obscureText;

  testWidgets('starts hidden, with the slashed eye and a Show tooltip',
      (tester) async {
    await pump(tester, PasswordField(
      fieldKey: const Key('pw'),
      controller: TextEditingController(),
    ));

    expect(obscured(tester, const Key('pw')), isTrue);
    // The icon reflects the CURRENT state: hidden means a slashed eye.
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('tapping reveals: open eye, Hide tooltip, text no longer masked',
      (tester) async {
    await pump(tester, PasswordField(
      fieldKey: const Key('pw'),
      controller: TextEditingController(),
    ));

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(obscured(tester, const Key('pw')), isFalse);
    // Open eye only once the characters are actually visible.
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(obscured(tester, const Key('pw')), isTrue);
  });

  testWidgets('two fields toggle independently', (tester) async {
    // Register has two. Revealing one must not reveal the other.
    await pump(tester, Column(children: [
      PasswordField(
          fieldKey: const Key('a'), controller: TextEditingController()),
      PasswordField(
          fieldKey: const Key('b'), controller: TextEditingController()),
    ]));

    await tester.tap(find.byTooltip('Show password').first);
    await tester.pump();

    expect(obscured(tester, const Key('a')), isFalse);
    expect(obscured(tester, const Key('b')), isTrue);
  });
}
