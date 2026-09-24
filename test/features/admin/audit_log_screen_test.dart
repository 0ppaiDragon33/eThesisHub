import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/audit_entry.dart';
import 'package:ethesishub/features/admin/audit_log_screen.dart';
import 'package:ethesishub/providers/admin_providers.dart';

Widget wrap(AsyncValue<List<AuditEntry>> log) => ProviderScope(
      overrides: [auditLogProvider.overrideWith((ref) => Stream.value(
            log.valueOrNull ?? const [],
          ))],
      child: const MaterialApp(home: Scaffold(body: AuditLogScreen())),
    );

AuditEntry entry(String id, String action, {String actor = 'coord-1'}) =>
    AuditEntry(
      id: id,
      actorUid: actor,
      action: action,
      targetType: 'user',
      targetId: 'u1',
      metadata: const {},
      at: DateTime(2026, 9, 20),
    );

void main() {
  testWidgets('lists the entries, action read as a sentence', (tester) async {
    await tester.pumpWidget(wrap(AsyncValue.data([
      entry('a', 'account.deactivated'),
      entry('b', 'invite.issued'),
    ])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auditRow-a')), findsOneWidget);
    expect(find.byKey(const Key('auditRow-b')), findsOneWidget);
    // `account.deactivated` -> `Account deactivated`.
    expect(find.text('Account deactivated'), findsOneWidget);
    expect(find.text('Invite issued'), findsOneWidget);
  });

  testWidgets('an empty log says so rather than going blank', (tester) async {
    await tester.pumpWidget(wrap(const AsyncValue.data([])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auditEmpty')), findsOneWidget);
  });
}
