import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/defence/schedule_defence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Seeds a thesis `t1` with leader `l1`, adviser `a1`, and two panelists
/// `p1`, `p2` (deliberately in an order that would sort differently, so a
/// reordering bug in the screen's snapshot would be caught). A `users/{uid}`
/// profile is added for each role a test signs in as. Pass `adviserUid:
/// null` to cover the (unreachable-through-the-app, but rules-relevant)
/// case of a thesis with no adviser on record.
Future<FakeFirebaseFirestore> seed({
  List<Map<String, dynamic>> chapters = const [],
  Object? adviserUid = 'a1',
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': adviserUid,
    'status': 'titleApproved',
    'panelistUids': <String>['p2', 'p1'],
    'memberNames': <String>[],
    'workingTitle': 'A Study of Things',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
  });
  await db.collection('users').doc('a1').set({
    'fullName': 'Dr. Adviser',
    'email': 'a1@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  await db.collection('users').doc('c1').set({
    'fullName': 'Coordinator One',
    'email': 'c1@isufst.edu.ph',
    'role': 'coordinator',
    'active': true,
  });
  for (final chapter in chapters) {
    await db
        .collection('theses/t1/documents')
        .doc(chapter['id'] as String)
        .set({
      'type': chapter['id'],
      'currentVersion': 1,
      'status': chapter['status'],
    });
  }
  return db;
}

// Without this override, `FirebaseAuth.instance` throws `[core/no-app]`
// because no app is initialised in a widget test, `authStateProvider`
// settles into AsyncError, and any uid read off it is silently null
// forever. See adviser_review_test.dart's `_wrap` for the same pattern.
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
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/schedule',
          routes: [
            GoRoute(
              path: '/schedule',
              // the app shell supplies the Scaffold in the real app.
              builder: (_, _) => Scaffold(
                  appBar: AppBar(title: const Text('Schedule a defence')),
                  body: const ScheduleDefenceScreen(thesisId: 't1')),
            ),
            // Matches the real path Task 11 registers for the defence room
            // (Task 8): '/defence/room/:defenceId'. If the screen's own
            // navigation target ever drifts from that path, this route
            // will not match and the test fails instead of silently
            // agreeing with whatever the screen happens to call.
            GoRoute(
              path: '/defence/room/:id',
              builder: (_, _) => const Scaffold(
                body: Center(
                    child: Text('defence room', key: Key('landedOnRoom'))),
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('only the coordinator sees the schedule control',
      (tester) async {
    final db = await seed();

    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheduleDefence')), findsNothing);

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheduleDefence')), findsOneWidget);
  });

  testWidgets('scheduling snapshots the panel and adviser from the thesis',
      (tester) async {
    final db = await seed();

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('defenceVenue')), 'Room 301');
    await tester.tap(find.byKey(const Key('scheduleDefence')));
    await tester.pumpAndSettle();

    final saved = await db.collection('defenses').get();
    expect(saved.docs, hasLength(1));
    final data = saved.docs.first.data();
    expect(data['panelUids'], ['p2', 'p1'],
        reason: 'must be the thesis\'s panelistUids verbatim, in its own '
            'order -- the create rule is an array equality that includes '
            'order');
    expect(data['adviserUid'], 'a1');
    expect(data['leaderUid'], 'l1');
  });

  testWidgets('an unready thesis warns but still schedules', (tester) async {
    final db = await seed(chapters: const [
      {'id': 'chapterI', 'status': 'approved'},
      {'id': 'chapterII', 'status': 'approved'},
    ]);

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();

    // preOral is the default selection, so no need to interact with the
    // SegmentedButton.
    expect(find.byKey(const Key('readinessWarning')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('defenceVenue')), 'Room 301');
    await tester.tap(find.byKey(const Key('scheduleDefence')));
    await tester.pumpAndSettle();

    final saved = await db.collection('defenses').get();
    expect(saved.docs, hasLength(1),
        reason: 'decision M3-3: an unready thesis still schedules');
  });

  testWidgets('a ready thesis shows no warning', (tester) async {
    final db = await seed(chapters: const [
      {'id': 'chapterI', 'status': 'approved'},
      {'id': 'chapterII', 'status': 'approved'},
      {'id': 'chapterIII', 'status': 'approved'},
    ]);

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();

    // preOral is the default selection; chapters I-III approved satisfies
    // its gate.
    expect(find.byKey(const Key('readinessWarning')), findsNothing);
  });

  testWidgets('an empty venue is refused before any write', (tester) async {
    final db = await seed();

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scheduleDefence')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Give the defence a venue'), findsOneWidget);
    expect((await db.collection('defenses').get()).docs, isEmpty);
  });

  testWidgets('a thesis with no adviser on record refuses before any write',
      (tester) async {
    final db = await seed(adviserUid: null);

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('defenceVenue')), 'Room 301');
    await tester.tap(find.byKey(const Key('scheduleDefence')));
    await tester.pumpAndSettle();

    // Not "permission-denied": the create rule would deny '' against a
    // stored null and blame the coordinator's authorization for a data
    // problem they cannot act on. This message names the real cause.
    expect(
        find.textContaining('This thesis has no adviser on record'),
        findsOneWidget);
    expect((await db.collection('defenses').get()).docs, isEmpty);
  });

  testWidgets('the thesis stream loading is shown, not collapsed into absent',
      (tester) async {
    // A stream that never emits: the widget stays in the loading state for
    // as long as the test looks at it, without pumpAndSettle racing past
    // it. fake_cloud_firestore settles inside a single pump, so a real
    // query cannot hold the frame open the way this StreamController does.
    final neverThesis = StreamController<Thesis?>();
    addTearDown(neverThesis.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'c1',
      overrides: [
        thesisByIdProvider('t1').overrideWith((ref) => neverThesis.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading thesis…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('defenceVenue')), findsNothing);
  });

  testWidgets(
      'the chapters stream loading is shown, not collapsed into ready',
      (tester) async {
    final neverChapters = StreamController<List<ThesisChapter>>();
    addTearDown(neverChapters.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'c1',
      overrides: [
        chaptersProvider('t1').overrideWith((ref) => neverChapters.stream),
      ],
    ));
    // Unlike the thesis-loading test above, thesisByIdProvider here is NOT
    // overridden -- it still has to resolve through the real auth stream
    // and the real fake-firestore query before the chapters branch is even
    // reached. Each of those is its own async gap, so one pump only gets
    // partway; pumping a few more times (never pumpAndSettle, which would
    // also drain the never-emitting chapters stream's non-existent event)
    // lets the thesis settle while leaving the chapters stream untouched.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading chapters…'), findsOneWidget);
    // Neither reading of the still-unknown chapters must show: no warning
    // (an empty list would read as notReady) and no silent "all clear".
    expect(find.byKey(const Key('readinessWarning')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    // The form itself is unaffected -- only the thesis stream gates it.
    expect(find.byKey(const Key('defenceVenue')), findsOneWidget);
  });
}
