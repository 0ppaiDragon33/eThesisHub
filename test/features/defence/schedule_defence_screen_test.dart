import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/features/defence/schedule_defence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Seeds a thesis `t1` with leader `l1`, adviser `a1`, and two panelists
/// `p1`, `p2` (deliberately in an order that would sort differently, so a
/// reordering bug in the screen's snapshot would be caught). A `users/{uid}`
/// profile is added for each role a test signs in as.
Future<FakeFirebaseFirestore> seed({
  List<Map<String, dynamic>> chapters = const [],
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
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
Widget _wrap(FakeFirebaseFirestore db, {required String uid}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
        )),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/schedule',
          routes: [
            GoRoute(
              path: '/schedule',
              builder: (_, _) => const ScheduleDefenceScreen(thesisId: 't1'),
            ),
            // A stand-in for the defence room, which Task 8 builds. Its
            // real path is not this test's concern; only that navigation
            // away from the form happens on success.
            GoRoute(
              path: '/defenses/:id',
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
}
