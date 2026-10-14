import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/platform/native_back.dart';

void main() {
  GoRouter router({String initial = '/overview'}) => GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(
            path: '/overview',
            builder: (_, _) => const Scaffold(body: Text('dashboard')),
          ),
          GoRoute(
            path: '/thesis/chapters',
            builder: (_, _) => const Scaffold(body: Text('chapters')),
          ),
          GoRoute(
            path: '/deep',
            builder: (_, _) => const Scaffold(body: Text('deep')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('login')),
          ),
        ],
      );

  testWidgets('pops a pushed screen and answers true', (tester) async {
    final r = router();
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    r.push('/deep');
    await tester.pumpAndSettle();
    expect(find.text('deep'), findsOneWidget);
    expect(r.canPop(), isTrue);

    final handled =
        await handleNativeBack(r, const MethodCall('popRoute'));
    await tester.pumpAndSettle();

    expect(handled, isTrue, reason: 'a deep screen was popped');
    expect(find.text('deep'), findsNothing);
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets('another top-level page goes to the dashboard, not the exit',
      (tester) async {
    final r = router(initial: '/thesis/chapters');
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    expect(r.canPop(), isFalse);

    final handled =
        await handleNativeBack(r, const MethodCall('popRoute'));
    await tester.pumpAndSettle();

    expect(handled, isTrue, reason: 'went to the dashboard instead');
    expect(find.text('dashboard'), findsOneWidget);
    expect(find.text('chapters'), findsNothing);
  });

  testWidgets('answers false on the dashboard', (tester) async {
    final r = router();
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    expect(r.canPop(), isFalse);
    final handled =
        await handleNativeBack(r, const MethodCall('popRoute'));
    expect(handled, isFalse,
        reason: 'nothing to pop; the native side handles the exit');
  });

  testWidgets('answers false signed out, where there is no dashboard',
      (tester) async {
    final r = router(initial: '/login');
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    expect(await handleNativeBack(r, const MethodCall('popRoute')), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('ignores an unrelated method', (tester) async {
    final r = router();
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    expect(await handleNativeBack(r, const MethodCall('somethingElse')),
        isNull);
  });
}
