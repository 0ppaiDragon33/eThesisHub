import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Seeds a `users/{uid}` profile for the given faculty uid, plus one
/// `defenses/{id}` doc with the given adviser/panel/scheduled time.
Future<void> _seedDefence(
  FakeFirebaseFirestore db, {
  required String id,
  required String adviserUid,
  required List<String> panelUids,
  required DateTime scheduledAt,
  String status = 'scheduled',
}) async {
  await db.collection('defenses').doc(id).set({
    'thesisId': 't-$id',
    'type': 'preOral',
    'scheduledAt': Timestamp.fromDate(scheduledAt),
    'venue': 'Room $id',
    'panelUids': panelUids,
    'adviserUid': adviserUid,
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
  });
}

Future<FakeFirebaseFirestore> _seedUser(String uid, {String role = 'faculty'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(uid).set({
    'fullName': 'Faculty $uid',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  return db;
}

// Without this override, `FirebaseAuth.instance` throws `[core/no-app]`
// because no app is initialised in a widget test -- see
// defence_room_screen_test.dart's `_wrap` for the same pattern.
Widget _wrap(
  FakeFirebaseFirestore db, {
  required String uid,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
        )),
        ...overrides,
      ],
      child: const MaterialApp(
        home: Scaffold(body: DefencesList()),
      ),
    );

void main() {
  testWidgets(
      'a faculty member sees defences from BOTH positions, including one '
      'added to the panel side alone after mount', (tester) async {
    final db = await _seedUser('f1');
    // Only the adviser-side defence exists at mount. A snapshot-once merge
    // (read the panelist side once with `.first`, re-run only when the
    // adviser stream ticks) would pass this alone -- the whole point of this
    // shape is that it stays live, so the assertion that actually catches
    // that is below: adding a PANEL-only defence after the widget has
    // already settled, with nothing on the adviser side changing.
    await _seedDefence(
      db,
      id: 'advised',
      adviserUid: 'f1',
      panelUids: const ['other'],
      scheduledAt: DateTime(2026, 9, 1, 9),
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-advised')), findsOneWidget);
    expect(find.byKey(const Key('defenceRow-paneled')), findsNothing);

    // Nothing about f1's adviser query changes here -- this write only
    // touches panelUids on a new document. A fan-in that only advances on
    // the adviser stream's own emissions would never see this and the
    // widget would stay stuck on just 'advised' forever.
    await _seedDefence(
      db,
      id: 'paneled',
      adviserUid: 'other',
      panelUids: const ['f1', 'p2'],
      scheduledAt: DateTime(2026, 9, 5, 9),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-advised')), findsOneWidget);
    expect(find.byKey(const Key('defenceRow-paneled')), findsOneWidget);
  });

  testWidgets('the list is soonest first', (tester) async {
    final db = await _seedUser('f1');
    // Seeded LATER-first on purpose: fake_cloud_firestore returns documents
    // in insertion order, so a fixture already sorted would pass even with
    // the sort deleted, proving nothing. Inserting 'later' before 'sooner'
    // forces the widget to actually reorder them.
    await _seedDefence(
      db,
      id: 'later',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 10, 1, 9),
    );
    await _seedDefence(
      db,
      id: 'sooner',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 9, 1, 9),
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    final sooner = find.byKey(const Key('defenceRow-sooner'));
    final later = find.byKey(const Key('defenceRow-later'));
    expect(sooner, findsOneWidget);
    expect(later, findsOneWidget);

    final ySooner = tester.getTopLeft(sooner).dy;
    final yLater = tester.getTopLeft(later).dy;
    expect(ySooner, lessThan(yLater),
        reason: 'the Sept 1 defence must render above the Oct 1 one, '
            'soonest first, regardless of insertion order');
  });

  testWidgets('an empty schedule says so rather than showing nothing',
      (tester) async {
    final db = await _seedUser('f1');

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noDefences')), findsOneWidget);
    expect(find.text('No defences scheduled'), findsOneWidget);
  });

  testWidgets('a loading schedule is not shown as empty', (tester) async {
    final db = await _seedUser('f1');
    // A stream that never emits: the widget stays in the loading state for
    // as long as the test looks at it, without pumpAndSettle racing past
    // it. fake_cloud_firestore settles inside a single pump, so a real
    // query cannot hold the frame open the way this StreamController does.
    final neverDefences = StreamController<List<Defence>>();
    addTearDown(neverDefences.close);

    await tester.pumpWidget(_wrap(
      db,
      uid: 'f1',
      overrides: [
        myDefencesProvider.overrideWith((ref) => neverDefences.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading your defences…'), findsOneWidget);
    expect(find.byKey(const Key('noDefences')), findsNothing);
    expect(find.text('No defences scheduled'), findsNothing);
  });

  testWidgets(
      'the leader\'s Open button goes to the consolidated route, not the '
      'raw room', (tester) async {
    // FIX 4: every role, students included, used to route into
    // `/defence/room/${d.id}` -- the raw live log. M3-2 forbids the group
    // from ever reading it; the group reads the adviser's consolidation.
    // `_seedDefence` snapshots `leaderUid: 'l1'`, so signing in as l1 is
    // what makes this the leader's own row.
    final db = await _seedUser('l1', role: 'student');
    await _seedDefence(
      db,
      id: 'd1',
      adviserUid: 'a1',
      panelUids: const ['p1'],
      scheduledAt: DateTime(2026, 9, 1, 9),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'l1', email: 'l1@isufst.edu.ph', isEmailVerified: true),
        )),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/defences',
          routes: [
            GoRoute(
              path: '/defences',
              builder: (_, _) => const Scaffold(body: DefencesList()),
            ),
            GoRoute(
              path: '/defence/room/:defenceId',
              builder: (context, state) => Scaffold(
                appBar: AppBar(
                  title: Text('Room ${state.pathParameters['defenceId']}'),
                ),
              ),
            ),
            GoRoute(
              path: '/defence/room/:defenceId/consolidated',
              builder: (context, state) => Scaffold(
                appBar: AppBar(
                  title: Text(
                      'Consolidated ${state.pathParameters['defenceId']}'),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('goToDefence-d1')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Consolidated d1'), findsOneWidget);
  });
}
