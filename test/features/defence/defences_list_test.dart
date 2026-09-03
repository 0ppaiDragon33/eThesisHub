import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Same shape as `approvedThesis()` in
/// `test/core/routing/deep_navigation_test.dart`, kept local: every
/// defence row now resolves its thesis's working title, and this is the
/// minimal doc `thesisByIdProvider` needs to resolve one.
Map<String, dynamic> _thesisDoc({
  required String leaderUid,
  required String workingTitle,
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': 'a1',
      'panelistUids': const <String>[],
      'memberNames': const <String>[],
      'workingTitle': workingTitle,
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': 'titleApproved',
    };

/// Seeds a `users/{uid}` profile for the given faculty uid, plus one
/// `defenses/{id}` doc with the given adviser/panel/scheduled time.
Future<void> _seedDefence(
  FakeFirebaseFirestore db, {
  required String id,
  required String adviserUid,
  required List<String> panelUids,
  DateTime? scheduledAt,
  String status = 'scheduled',
  String type = 'preOral',
  String? thesisId,
  DateTime? evaluationsReleasedAt,
}) async {
  await db.collection('defenses').doc(id).set({
    'thesisId': thesisId ?? 't-$id',
    'type': type,
    'scheduledAt':
        scheduledAt == null ? null : Timestamp.fromDate(scheduledAt),
    'venue': 'Room $id',
    'panelUids': panelUids,
    'adviserUid': adviserUid,
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    if (evaluationsReleasedAt != null)
      'evaluationsReleasedAt': Timestamp.fromDate(evaluationsReleasedAt),
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

  // ---- M4: the evaluation affordances on a row ----
  //
  // These two keys shipped with no test at all. An entry point nothing
  // asserts is exactly the shape of the M2 leader upload flow that nothing
  // navigated to, caught only in final review.

  testWidgets('a panelist on a completed defence is offered the sheet',
      (tester) async {
    final db = await _seedUser('p1');
    await _seedDefence(db,
        id: 'd1',
        adviserUid: 'a1',
        panelUids: const ['p1'],
        status: 'completed',
        scheduledAt: DateTime(2026, 9, 1, 9));

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToEvaluate-d1')), findsOneWidget);
  });

  testWidgets('the adviser is never offered the sheet -- they cannot score',
      (tester) async {
    final db = await _seedUser('a1');
    await _seedDefence(db,
        id: 'd1',
        adviserUid: 'a1',
        panelUids: const ['p1'],
        status: 'completed',
        scheduledAt: DateTime(2026, 9, 1, 9));

    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToEvaluate-d1')), findsNothing);
    // The adviser's own affordance, offered from the moment it closes.
    expect(find.byKey(const Key('goToGrades-d1')), findsOneWidget);
  });

  testWidgets('an open defence offers neither affordance', (tester) async {
    final db = await _seedUser('p1');
    await _seedDefence(db,
        id: 'd1',
        adviserUid: 'a1',
        panelUids: const ['p1'],
        status: 'inProgress',
        scheduledAt: DateTime(2026, 9, 1, 9));

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToEvaluate-d1')), findsNothing);
    expect(find.byKey(const Key('goToGrades-d1')), findsNothing);
  });

  // D39's seal, in the row: a panelist reaches the grades only once the
  // adviser has released them.
  testWidgets('a panelist reaches the grades only once they are released',
      (tester) async {
    final db = await _seedUser('p1');
    await _seedDefence(db,
        id: 'd1',
        adviserUid: 'a1',
        panelUids: const ['p1'],
        status: 'completed',
        scheduledAt: DateTime(2026, 9, 1, 9));

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToGrades-d1')), findsNothing);

    await db.collection('defenses').doc('d1').update({
      'evaluationsReleasedAt': Timestamp.fromDate(DateTime(2026, 9, 24)),
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToGrades-d1')), findsOneWidget);
  });

  // Finding 7, in the row. The rules grant both roles the released
  // evaluations and §6 names both as viewers, but the row offered them
  // nothing.
  testWidgets(
      'the coordinator and the dean reach the grades once released',
      (tester) async {
    for (final entry in {'c1': 'coordinator', 'dn1': 'dean'}.entries) {
      final db = await _seedUser(entry.key, role: entry.value);
      await _seedDefence(db,
          id: 'd1',
          adviserUid: 'a1',
          panelUids: const ['p1'],
          status: 'completed',
          scheduledAt: DateTime(2026, 9, 1, 9),
          evaluationsReleasedAt: DateTime(2026, 9, 24));

      await tester.pumpWidget(_wrap(db, uid: entry.key));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goToGrades-d1')), findsOneWidget,
          reason: entry.key);
      expect(find.byKey(const Key('goToEvaluate-d1')), findsNothing,
          reason: entry.key);
    }
  });

  testWidgets('the coordinator is offered nothing before release',
      (tester) async {
    final db = await _seedUser('c1', role: 'coordinator');
    await _seedDefence(db,
        id: 'd1',
        adviserUid: 'a1',
        panelUids: const ['p1'],
        status: 'completed',
        scheduledAt: DateTime(2026, 9, 1, 9));

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToGrades-d1')), findsNothing);
  });

  // The leader never reaches either: D47 puts the numbers out of reach
  // rather than merely unrendered.
  testWidgets('the thesis leader is offered neither affordance',
      (tester) async {
    final db = await _seedUser('l1', role: 'student');
    await _seedDefence(db,
        id: 'd1',
        adviserUid: 'a1',
        panelUids: const ['p1'],
        status: 'completed',
        scheduledAt: DateTime(2026, 9, 1, 9),
        evaluationsReleasedAt: DateTime(2026, 9, 24));

    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToEvaluate-d1')), findsNothing);
    expect(find.byKey(const Key('goToGrades-d1')), findsNothing);
  });

  testWidgets('both affordances navigate where they say they do',
      (tester) async {
    final db = await _seedUser('p1');
    await _seedDefence(db,
        id: 'd1',
        adviserUid: 'a1',
        panelUids: const ['p1'],
        status: 'completed',
        scheduledAt: DateTime(2026, 9, 1, 9),
        evaluationsReleasedAt: DateTime(2026, 9, 24));

    Widget routed() => ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(db),
            firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                  uid: 'p1',
                  email: 'p1@isufst.edu.ph',
                  isEmailVerified: true),
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
                  path: '/defence/room/:defenceId/evaluate',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(
                        title: Text(
                            'Evaluate ${state.pathParameters['defenceId']}')),
                  ),
                ),
                GoRoute(
                  path: '/defence/room/:defenceId/grades',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(
                        title: Text(
                            'Grades ${state.pathParameters['defenceId']}')),
                  ),
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(routed());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goToEvaluate-d1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Evaluate d1'), findsOneWidget);

    await tester.pumpWidget(routed());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goToGrades-d1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Grades d1'), findsOneWidget);
  });

  testWidgets('a row shows the thesis working title, not the defence type',
      (tester) async {
    final db = await _seedUser('f1');
    await db
        .collection('theses')
        .doc('t-d1')
        .set(_thesisDoc(leaderUid: 'l1', workingTitle: 'On Widget Trees'));
    await _seedDefence(
      db,
      id: 'd1',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 9, 1, 9),
      thesisId: 't-d1',
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.text('On Widget Trees'), findsOneWidget);
    // The type moved beneath the title rather than disappearing.
    expect(find.textContaining('Pre-oral defence'), findsOneWidget);
  });

  testWidgets(
      'a row shows a pending placeholder, never blank, while the title '
      'is still loading', (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(
      db,
      id: 'd1',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 9, 1, 9),
      thesisId: 't-d1',
    );
    // A stream that never emits, standing in for the per-thesis read: the
    // defence list itself settles (fake_cloud_firestore resolves inside a
    // pump), but the title must not render as blank while ITS OWN stream is
    // still pending.
    final neverThesis = StreamController<Thesis?>();
    addTearDown(neverThesis.close);

    await tester.pumpWidget(_wrap(
      db,
      uid: 'f1',
      overrides: [
        thesisByIdProvider.overrideWith((ref, arg) => neverThesis.stream),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('On Widget Trees'), findsNothing);
    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);
    expect(find.text('Loading title…'), findsOneWidget);
  });

  testWidgets('cancelled defences stay visible, struck through and muted',
      (tester) async {
    final db = await _seedUser('f1');
    await db
        .collection('theses')
        .doc('t-d1')
        .set(_thesisDoc(leaderUid: 'l1', workingTitle: 'Called Off Study'));
    await _seedDefence(
      db,
      id: 'd1',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 9, 1, 9),
      thesisId: 't-d1',
      status: 'cancelled',
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);
    final title = tester.widget<Text>(find.text('Called Off Study'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets(
      'the list is grouped into Pre-oral and Final sections, each '
      'soonest first', (tester) async {
    final db = await _seedUser('f1');
    // Seeded out of both type-order and date-order on purpose: a fixture
    // that happened to already be sorted would pass with the grouping or
    // the sort deleted.
    await _seedDefence(
      db,
      id: 'finalLater',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 10, 1, 9),
      type: 'final',
    );
    await _seedDefence(
      db,
      id: 'preOralLater',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 10, 2, 9),
    );
    await _seedDefence(
      db,
      id: 'finalSooner',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 9, 1, 9),
      type: 'final',
    );
    await _seedDefence(
      db,
      id: 'preOralSooner',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 9, 2, 9),
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    final preOralHeading = find.text('Pre-oral');
    final finalHeading = find.text('Final');
    expect(preOralHeading, findsOneWidget);
    expect(finalHeading, findsOneWidget);

    // Pre-oral section renders above the Final section.
    expect(tester.getTopLeft(preOralHeading).dy,
        lessThan(tester.getTopLeft(finalHeading).dy));

    // Within each section, soonest first.
    final preOralSooner = find.byKey(const Key('defenceRow-preOralSooner'));
    final preOralLater = find.byKey(const Key('defenceRow-preOralLater'));
    expect(tester.getTopLeft(preOralSooner).dy,
        lessThan(tester.getTopLeft(preOralLater).dy));

    final finalSooner = find.byKey(const Key('defenceRow-finalSooner'));
    final finalLater = find.byKey(const Key('defenceRow-finalLater'));
    expect(tester.getTopLeft(finalSooner).dy,
        lessThan(tester.getTopLeft(finalLater).dy));
  });

  testWidgets('a section with nothing in it is omitted, not shown empty',
      (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(
      db,
      id: 'onlyFinal',
      adviserUid: 'f1',
      panelUids: const [],
      scheduledAt: DateTime(2026, 9, 1, 9),
      type: 'final',
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.text('Final'), findsOneWidget);
    expect(find.text('Pre-oral'), findsNothing);
  });
}
