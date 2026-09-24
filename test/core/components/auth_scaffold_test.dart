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

  testWidgets('wide: route panel beside the card', (tester) async {
    await pumpAt(tester, const Size(1200, 900));

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('form body'), findsOneWidget);
    // The wide layout adds the route panel — the five desks a thesis passes
    // through, under its own sentence — beside the form. The narrow band's
    // sentence (`brandSentence`) is a different line and is not shown here.
    expect(find.text('Researchers'), findsOneWidget);
    expect(find.text('Every thesis, from nomination to the archive.'), findsOneWidget);
    expect(find.text(AuthScaffold.brandSentence), findsNothing);
  });

  testWidgets('narrow: band above the card, no route panel', (tester) async {
    await pumpAt(tester, const Size(400, 900));

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('form body'), findsOneWidget);
    // The narrow band carries the wordmark and the product sentence, but not
    // the wide route panel — a phone has no room for the five desks.
    expect(find.text(AuthScaffold.brandSentence), findsOneWidget);
    expect(find.text('Researchers'), findsNothing);
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

  // D82's breakpoint, from both sides. An off-by-one here — `>` where `>=`
  // was meant — would swap the layout on a whole class of tablet widths and
  // no other test in this file would notice.
  testWidgets('switches layout exactly at the breakpoint', (tester) async {
    // The route panel (wide-only) is the discriminator: the brand sentence
    // shows at both widths now, so it can no longer tell the layouts apart.
    await pumpAt(tester, const Size(AuthScaffold.wideBreakpoint - 1, 900));
    expect(find.text('Researchers'), findsNothing);

    await pumpAt(tester, const Size(AuthScaffold.wideBreakpoint, 900));
    expect(find.text('Researchers'), findsOneWidget);
  });

  // D83, and the question this whole design was challenged on: with the
  // keyboard up, can you still see the field you are typing in?
  //
  // Nothing here simulates a keyboard beyond shrinking the viewport, because
  // nothing in AuthScaffold detects one. The chain being pinned is entirely
  // the framework's: Scaffold shrinks the viewport to the space above the
  // inset, the focused EditableText calls Scrollable.ensureVisible on itself,
  // and the band scrolls away because it is a CHILD of the scroll view rather
  // than a sibling pinned above it. Break any link — pin the band outside the
  // scrollable, or set resizeToAvoidBottomInset: false — and this fails.
  testWidgets('a focused field stays visible above a keyboard-sized inset',
      (tester) async {
    const inset = 300.0;
    const height = 700.0;

    tester.view.physicalSize = const Size(400, height);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: inset);
    addTearDown(tester.view.reset);

    final last = FocusNode();
    addTearDown(last.dispose);

    await tester.pumpWidget(MaterialApp(
      home: AuthScaffold(
        title: 'Create account',
        children: [
          const TextField(),
          const TextField(),
          const TextField(),
          const TextField(),
          // Register's last field starts well below the fold on a phone, which
          // is the case that actually hurts. The spacer forces it there rather
          // than hoping five fields happen to overflow.
          const SizedBox(height: 900),
          TextField(focusNode: last),
        ],
      ),
    ));

    last.requestFocus();
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextField).last);
    expect(field.bottom, lessThanOrEqualTo(height - inset),
        reason: 'the focused field is under the keyboard');
    expect(field.top, greaterThanOrEqualTo(0.0),
        reason: 'the focused field scrolled off the top');
    expect(tester.takeException(), isNull);
  });
}
