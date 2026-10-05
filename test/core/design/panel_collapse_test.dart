import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_theme.dart';

Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _panel = Panel(
  title: 'All theses',
  subtitle: 'Every group in the college',
  trailing: Text('TRAILING'),
  child: Text('BODY'),
);

void main() {
  testWidgets('without a collapse marker a panel draws as always',
      (tester) async {
    await tester.pumpWidget(host(_panel));
    expect(find.text('BODY'), findsOneWidget);
    expect(find.text('Every group in the college'), findsOneWidget);
    expect(find.text('TRAILING'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('a disabled marker changes nothing', (tester) async {
    await tester.pumpWidget(host(const PanelCollapse(
      enabled: false,
      id: 'x',
      peek: '24',
      child: _panel,
    )));
    expect(find.text('BODY'), findsOneWidget);
    expect(find.text('24'), findsNothing);
  });

  testWidgets('folded: title and peek only; a tap opens it, another closes it',
      (tester) async {
    await tester.pumpWidget(host(const PanelCollapse(
      enabled: true,
      id: 'theses',
      peek: '24',
      child: _panel,
    )));

    expect(find.text('All theses'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('BODY'), findsNothing);
    expect(find.text('Every group in the college'), findsNothing);
    expect(find.text('TRAILING'), findsNothing);

    await tester.tap(find.byKey(const Key('panelToggle-theses')));
    await tester.pumpAndSettle();
    expect(find.text('BODY'), findsOneWidget);
    expect(find.text('Every group in the college'), findsOneWidget);
    expect(find.text('TRAILING'), findsOneWidget);
    expect(find.text('24'), findsNothing, reason: 'peek hides once open');

    await tester.tap(find.byKey(const Key('panelToggle-theses')));
    await tester.pumpAndSettle();
    expect(find.text('BODY'), findsNothing);
  });

  testWidgets('initiallyOpen starts open', (tester) async {
    await tester.pumpWidget(host(const PanelCollapse(
      enabled: true,
      id: 'stages',
      initiallyOpen: true,
      child: _panel,
    )));
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('openOn opens a folded panel when it notifies', (tester) async {
    final trigger = ValueNotifier<int>(0);
    addTearDown(trigger.dispose);
    await tester.pumpWidget(host(PanelCollapse(
      enabled: true,
      id: 'theses',
      openOn: trigger,
      child: _panel,
    )));
    expect(find.text('BODY'), findsNothing);

    trigger.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('a panel inside an open one draws normally', (tester) async {
    await tester.pumpWidget(host(const PanelCollapse(
      enabled: true,
      id: 'outer',
      initiallyOpen: true,
      child: Panel(
        title: 'Outer',
        child: Panel(title: 'Inner', child: Text('INNER BODY')),
      ),
    )));
    expect(find.text('INNER BODY'), findsOneWidget);
    expect(find.byKey(const Key('panelToggle-outer')), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget,
        reason: 'only the outer panel folds');
  });

  testWidgets('a panel with no title never folds', (tester) async {
    await tester.pumpWidget(host(const PanelCollapse(
      enabled: true,
      id: 'x',
      child: Panel(child: Text('BODY')),
    )));
    expect(find.text('BODY'), findsOneWidget);
  });
}
