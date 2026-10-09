import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/features/dashboard/faculty_mode_switch.dart';
import 'package:ethesishub/features/dashboard/mode_switch_transition.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

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
  group('switching shows a short "Switching to … View" screen', () {
    Future<SharedPreferences> pumpSwitchable(
      WidgetTester tester,
      FacultyMode mode, {
      required Size size,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
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
      return prefs;
    }

    testWidgets('to Panelist View, then it clears itself', (tester) async {
      final prefs = await pumpSwitchable(tester, FacultyMode.adviser,
          size: const Size(360, 800));

      await tester.tap(find.byKey(const Key('facultyModeCompact')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('modeSwitchScreen')), findsOneWidget);
      expect(find.text('Switching to Panelist View'), findsOneWidget);
      expect(find.text('Opening your panels…'), findsOneWidget);
      expect(prefs.getString('faculty_mode'), isNotNull,
          reason: 'the mode itself changed straight away');

      await tester.pump(modeSwitchHold);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modeSwitchScreen')), findsNothing);
    });

    testWidgets('to Adviser View from the wide switch', (tester) async {
      await pumpSwitchable(tester, FacultyMode.panelist,
          size: const Size(1400, 900));

      await tester.tap(find.text('Adviser'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Switching to Adviser View'), findsOneWidget);
      expect(find.text('Opening your advisees…'), findsOneWidget);

      await tester.pump(modeSwitchHold);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modeSwitchScreen')), findsNothing);
    });

    testWidgets('tapping the mode already in force shows nothing',
        (tester) async {
      await pumpSwitchable(tester, FacultyMode.adviser,
          size: const Size(1400, 900));

      await tester.tap(find.text('Adviser'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modeSwitchScreen')), findsNothing);
    });
  });
}
