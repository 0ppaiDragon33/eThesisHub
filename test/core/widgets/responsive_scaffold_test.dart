import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';

Widget harness() {
  return MaterialApp(
    home: ResponsiveScaffold(
      title: 'Dashboard',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        NavDestination(label: 'Home', icon: Icons.home),
        NavDestination(label: 'Theses', icon: Icons.description),
      ],
      body: const Text('body'),
    ),
  );
}

void main() {
  testWidgets('uses a bottom navigation bar on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses a navigation rail on wide screens', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
