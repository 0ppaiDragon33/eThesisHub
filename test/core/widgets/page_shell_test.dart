import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';

void main() {
  testWidgets('defaults to the form measure', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: PageShell(children: [SizedBox(key: Key('content'), height: 40)]),
      ),
    ));

    expect(tester.getSize(find.byKey(const Key('content'))).width,
        lessThanOrEqualTo(AppTokens.measure));
  });

  testWidgets('honours a wider measure when asked', (tester) async {
    // Dashboards need it; forms must not get it by accident, which is why
    // the default above is asserted too.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: PageShell(
          maxWidth: AppTokens.measureWide,
          children: [SizedBox(key: Key('content'), height: 40)],
        ),
      ),
    ));

    expect(tester.getSize(find.byKey(const Key('content'))).width,
        greaterThan(AppTokens.measure));
  });

  testWidgets('renders an optional kicker above the title', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PageShell(
          kicker: 'Dean',
          title: 'Approvals',
          children: [Text('body')],
        ),
      ),
    ));

    expect(find.text('Dean'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
  });

  testWidgets('omitting the kicker changes nothing', (tester) async {
    // 26 screens already call PageShell without one; this pins that the new
    // parameter is genuinely optional rather than quietly required.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PageShell(title: 'Approvals', children: [Text('body')]),
      ),
    ));

    expect(find.text('Approvals'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
