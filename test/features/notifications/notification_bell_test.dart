import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/notifications/notification_bell.dart';
import 'package:ethesishub/providers/notification_providers.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required int unread}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unreadNotificationCountProvider.overrideWithValue(unread),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: NotificationBell())),
            GoRoute(path: '/notifications', builder: (_, _) => const Scaffold(body: Text('Notifications'))),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows no badge when nothing is unread', (tester) async {
    await pump(tester, unread: 0);
    expect(find.byKey(const Key('notificationBellBadge')), findsNothing);
  });

  testWidgets('shows the unread count as a badge', (tester) async {
    await pump(tester, unread: 3);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping the bell navigates to /notifications', (tester) async {
    await pump(tester, unread: 1);
    await tester.tap(find.byKey(const Key('notificationBell')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
