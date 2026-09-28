import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/features/dashboard/faculty_mode_switch.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';

/// Pumps the switch at a narrow width (below the rail breakpoint), in the
/// given mode, with both capabilities so the control renders.
Future<void> pumpCompact(WidgetTester tester, FacultyMode mode) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      effectiveFacultyModeProvider.overrideWith((ref) => Future.value(mode)),
      facultyHoldsBothCapabilitiesProvider
          .overrideWith((ref) => Future.value(true)),
      pendingInOtherModeProvider.overrideWith((ref) => Future.value(0)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: FacultyModeSwitch(location: '/thesis/chapters'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the compact bar shows A in adviser mode', (tester) async {
    await pumpCompact(tester, FacultyMode.adviser);
    expect(find.byKey(const Key('facultyModeCompact')), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('P'), findsNothing);
  });

  testWidgets('the compact bar shows P in panelist mode', (tester) async {
    await pumpCompact(tester, FacultyMode.panelist);
    expect(find.text('P'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('the wide bar keeps the labelled segmented switch',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        effectiveFacultyModeProvider
            .overrideWith((ref) => Future.value(FacultyMode.adviser)),
        facultyHoldsBothCapabilitiesProvider
            .overrideWith((ref) => Future.value(true)),
        pendingInOtherModeProvider.overrideWith((ref) => Future.value(0)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: FacultyModeSwitch(location: '/advisees')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('facultyModeSegmented')), findsOneWidget);
    expect(find.text('Adviser'), findsOneWidget);
    expect(find.text('Panelist'), findsOneWidget);
  });
}
