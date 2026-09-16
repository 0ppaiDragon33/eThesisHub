import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/components/brand.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: AuthScaffold(
        title: 'Sign in',
        subtitle: 'Use your ISUFST account.',
        children: [Text('form body')],
      ),
    ));
  }

  testWidgets('wide: brand pane beside the card', (tester) async {
    await pumpAt(tester, const Size(1200, 900));

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('form body'), findsOneWidget);
    // The sentence only appears where the pane has room for it.
    expect(find.text(AuthScaffold.brandSentence), findsOneWidget);
  });

  testWidgets('narrow: band above the card, no sentence', (tester) async {
    await pumpAt(tester, const Size(400, 900));

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('form body'), findsOneWidget);
    // A phone band is a band, not a billboard: the emblem and wordmark only.
    expect(find.text(AuthScaffold.brandSentence), findsNothing);
  });

  testWidgets('the emblem appears at both widths', (tester) async {
    await pumpAt(tester, const Size(1200, 900));
    expect(find.byType(BrandEmblem), findsOneWidget);

    await pumpAt(tester, const Size(400, 900));
    expect(find.byType(BrandEmblem), findsOneWidget);
  });

  // D83. The band is inside the scroll view and the Scaffold keeps Flutter's
  // default resize behaviour, so a keyboard shrinks the viewport and the band
  // scrolls away rather than eating the space the form needs. This pins the
  // structure that makes that true.
  testWidgets('the whole narrow layout scrolls, band included', (tester) async {
    await pumpAt(tester, const Size(400, 900));

    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsWidgets);
    // The emblem must be INSIDE a scroll view, not pinned above one.
    expect(
      find.ancestor(of: find.byType(BrandEmblem), matching: scrollable),
      findsWidgets,
    );
  });

  testWidgets('keeps the default resizeToAvoidBottomInset', (tester) async {
    await pumpAt(tester, const Size(400, 900));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    // Null means "use Flutter's default (true)". Setting it false is the bug
    // this pins against: it is what puts a focused field under the keyboard.
    expect(scaffold.resizeToAvoidBottomInset, anyOf(isNull, isTrue));
  });

  testWidgets('survives a keyboard-sized bottom inset', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: AuthScaffold(
        title: 'Create account',
        children: [
          _FieldStub(), _FieldStub(), _FieldStub(),
          _FieldStub(), _FieldStub(),
        ],
      ),
    ));

    // Five fields, a shrunken viewport and no overflow: the layout gives way
    // by scrolling rather than by painting outside itself.
    expect(tester.takeException(), isNull);
  });
}

/// A field-sized block, so the inset test exercises real height rather than
/// a one-line Text.
class _FieldStub extends StatelessWidget {
  const _FieldStub({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: 72);
}
