import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final _monday = DateTime(2026, 8, 24, 9);

Defence defence({
  required String id,
  required DateTime? scheduledAt,
  DefenceStatus status = DefenceStatus.scheduled,
}) =>
    Defence(
      id: id,
      thesisId: 't1',
      type: DefenceType.preOral,
      venue: 'AVR',
      panelUids: const ['p1'],
      adviserUid: 'a1',
      leaderUid: 'l1',
      status: status,
      createdBy: 'c1',
      scheduledAt: scheduledAt,
    );

void main() {
  group('defencesThisWeek', () {
    // The bug this pins: all three copies of this filter counted cancelled
    // and completed defences as defences THIS WEEK, while the student's own
    // "next defence" filtered `!d.status.isTerminal` correctly all along.
    // A defence called off on Monday still showed on three dashboards.
    test('excludes a cancelled defence inside the window', () {
      final result = defencesThisWeek(
        [
          defence(
            id: 'cancelled',
            scheduledAt: _monday.add(const Duration(days: 2)),
            status: DefenceStatus.cancelled,
          ),
        ],
        now: _monday,
      );
      expect(result, isEmpty);
    });

    test('excludes a completed defence inside the window', () {
      final result = defencesThisWeek(
        [
          defence(
            id: 'completed',
            scheduledAt: _monday.add(const Duration(days: 1)),
            status: DefenceStatus.completed,
          ),
        ],
        now: _monday,
      );
      expect(result, isEmpty);
    });

    test('keeps scheduled and in-progress defences inside the window', () {
      final result = defencesThisWeek(
        [
          defence(id: 'today', scheduledAt: _monday),
          defence(
            id: 'inProgress',
            scheduledAt: _monday.add(const Duration(days: 3)),
            status: DefenceStatus.inProgress,
          ),
        ],
        now: _monday,
      );
      expect(result.map((d) => d.id), ['today', 'inProgress']);
    });

    test('excludes defences outside the window and those with no date', () {
      final result = defencesThisWeek(
        [
          defence(
            id: 'yesterday',
            scheduledAt: _monday.subtract(const Duration(days: 1)),
          ),
          defence(
            id: 'nextWeek',
            scheduledAt: _monday.add(const Duration(days: 7)),
          ),
          defence(id: 'undated', scheduledAt: null),
        ],
        now: _monday,
      );
      expect(result, isEmpty);
    });
  });

  group('OverviewGreeting', () {
    // Spec §6: nothing on an overview may depend on `users/{uid}` existing.
    testWidgets('falls back to a plain greeting with no profile document',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OverviewGreeting()),
        ),
      ));
      await tester.pump();

      expect(find.text('Good day'), findsOneWidget);
    });

    testWidgets('uses the first whitespace-separated token of fullName',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(AppUser(
                uid: 'u1',
                fullName: '  Maria  Elena  Armada ',
                email: 'm@isufst.edu.ph',
                role: UserRole.dean,
                active: true,
                createdAt: _monday,
              ))),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OverviewGreeting()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Good day, Maria'), findsOneWidget);
    });
  });
}
