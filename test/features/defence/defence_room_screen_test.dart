import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defence_room_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Seeds a thesis `t1`, a defence `d1` on it with adviser `a1`, panel
/// `[p1, p2]`, leader `l1`, coordinator `c1`, and `users/{uid}` profiles for
/// each role a test signs in as. `status` defaults to `inProgress` because
/// most of these tests are about the open comment log; the scheduling and
/// completion tests override it explicitly.
Future<FakeFirebaseFirestore> seed({
  String status = 'inProgress',
  List<Map<String, String>> comments = const [],
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'status': 'titleApproved',
    'panelistUids': <String>['p1', 'p2'],
    'memberNames': <String>[],
    'workingTitle': 'A Study of Things',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
  });
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'preOral',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
    'venue': 'Room 301',
    'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
  });
  await db.collection('users').doc('a1').set({
    'fullName': 'Dr. Adviser',
    'email': 'a1@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  await db.collection('users').doc('p1').set({
    'fullName': 'Panelist One',
    'email': 'p1@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  await db.collection('users').doc('c1').set({
    'fullName': 'Coordinator One',
    'email': 'c1@isufst.edu.ph',
    'role': 'coordinator',
    'active': true,
  });
  await db.collection('users').doc('dn1').set({
    'fullName': 'Dean One',
    'email': 'dn1@isufst.edu.ph',
    'role': 'dean',
    'active': true,
  });

  for (var i = 0; i < comments.length; i++) {
    final c = comments[i];
    await db.collection('defenses/d1/comments').doc('cm$i').set({
      'authorUid': c['authorUid'],
      'authorName': c['authorName'],
      'authorPosition': c['authorPosition'],
      'body': c['body'],
      'createdAt':
          Timestamp.fromDate(DateTime(2026, 8, 20, 9, i)), // ordered
    });
  }
  return db;
}

// Without this override, `FirebaseAuth.instance` throws `[core/no-app]`
// because no app is initialised in a widget test, `authStateProvider`
// settles into AsyncError, and any uid read off it is silently null
// forever. See schedule_defence_screen_test.dart's `_wrap` for the same
// pattern.
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
        home: DefenceRoomScreen(defenceId: 'd1'),
      ),
    );

void main() {
  testWidgets('the log is live for the panel', (tester) async {
    final db = await seed();
    final comments = db.collection('defenses/d1/comments');

    // Seeded newest-first on purpose. fake_cloud_firestore returns
    // documents in insertion order, so a fixture inserted already-sorted
    // would pass with the repository's sort deleted, proving nothing: this
    // order forces the screen (via the repository's chronological sort) to
    // actually reorder them to prove it works.
    await comments.doc('cm1').set({
      'authorUid': 'p1',
      'authorName': 'Panelist One',
      'authorPosition': 'Panel Member',
      'body': 'Methodology looks solid.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 9, 20)),
    });
    await comments.doc('cm0').set({
      'authorUid': 'a1',
      'authorName': 'Dr. Adviser',
      'authorPosition': 'Adviser',
      'body': 'Please tighten chapter two.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 9, 10)),
    });

    await tester.pumpWidget(_wrap(db, uid: 'p2'));
    await tester.pumpAndSettle();

    final row0 = find.byKey(const Key('commentRow-cm0'));
    final row1 = find.byKey(const Key('commentRow-cm1'));
    expect(row0, findsOneWidget);
    expect(row1, findsOneWidget);

    // Oldest first, by widget position: cm0 (9:10) sits above cm1 (9:20)
    // even though cm1 was inserted first.
    final y0 = tester.getTopLeft(row0).dy;
    final y1 = tester.getTopLeft(row1).dy;
    expect(y0, lessThan(y1),
        reason: 'cm0 (created 9:10) must render above cm1 (created 9:20), '
            'oldest first, regardless of insertion order');

    // Body order, not just position: names what went wrong if the log ever
    // renders in insertion order instead of chronological order.
    final bodies = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .toList();
    final adviserIndex =
        bodies.indexWhere((t) => t.contains('Please tighten chapter two.'));
    final panelIndex =
        bodies.indexWhere((t) => t.contains('Methodology looks solid.'));
    expect(adviserIndex, greaterThanOrEqualTo(0));
    expect(panelIndex, greaterThanOrEqualTo(0));
    expect(adviserIndex, lessThan(panelIndex),
        reason: 'the 9:10 comment must be laid out before the 9:20 comment');
  });

  testWidgets('the comment box is absent while the defence is scheduled',
      (tester) async {
    final db = await seed(status: 'scheduled');

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('commentBody')), findsNothing);
    expect(find.byKey(const Key('commentReason')), findsOneWidget);
  });

  testWidgets('the comment box appears once the defence is in progress',
      (tester) async {
    final db = await seed(status: 'inProgress');

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('commentBody')), findsOneWidget);
    expect(find.byKey(const Key('postComment')), findsOneWidget);
  });

  testWidgets('the comment box is gone again once completed', (tester) async {
    final db = await seed(status: 'completed');

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('commentBody')), findsNothing);
    expect(find.textContaining('closed'), findsOneWidget);
  });

  testWidgets('only the coordinator sees open and close', (tester) async {
    final scheduled = await seed(status: 'scheduled');
    await tester.pumpWidget(_wrap(scheduled, uid: 'p1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openDefence')), findsNothing);
    expect(find.byKey(const Key('closeDefence')), findsNothing);

    final inProgress = await seed(status: 'inProgress');
    await tester.pumpWidget(_wrap(inProgress, uid: 'p1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openDefence')), findsNothing);
    expect(find.byKey(const Key('closeDefence')), findsNothing);

    await tester.pumpWidget(_wrap(scheduled, uid: 'c1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openDefence')), findsOneWidget);
    expect(find.byKey(const Key('closeDefence')), findsNothing);

    await tester.pumpWidget(_wrap(inProgress, uid: 'c1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openDefence')), findsNothing);
    expect(find.byKey(const Key('closeDefence')), findsOneWidget);
  });

  testWidgets(
      'posting a comment writes it in the author\'s own name and position',
      (tester) async {
    final db = await seed();

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('commentBody')), 'Great defence overall.');
    await tester.tap(find.byKey(const Key('postComment')));
    await tester.pumpAndSettle();

    final saved = await db.collection('defenses/d1/comments').get();
    expect(saved.docs, hasLength(1));
    final data = saved.docs.first.data();
    expect(data['authorUid'], 'p1');
    expect(data['authorPosition'], 'Panel Member');
    expect(data['authorName'], 'Panelist One');
    expect(data['body'], 'Great defence overall.');
  });

  testWidgets(
      'the thesis leader never sees the comment box, even in progress',
      (tester) async {
    // inProgress is the one status where every other role (panelist,
    // adviser, coordinator, dean) DOES get the box -- see the test above.
    // The leader is not the adviser and not in panelUids, so
    // _authorPositionFor returns null and the box must stay hidden: the
    // rules deny a leader commenting on their own defence, and a control
    // that is visible and always fails is worse than none.
    final db = await seed(status: 'inProgress');
    await db.collection('users').doc('l1').set({
      'fullName': 'Leader One',
      'email': 'l1@isufst.edu.ph',
      'role': 'student',
      'active': true,
    });

    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('commentBody')), findsNothing);
    expect(find.byKey(const Key('postComment')), findsNothing);
    expect(find.byKey(const Key('commentReason')), findsOneWidget);
  });

  testWidgets('the defence stream loading is shown, not collapsed into absent',
      (tester) async {
    // A stream that never emits: the widget stays in the loading state for
    // as long as the test looks at it, without pumpAndSettle racing past
    // it. fake_cloud_firestore settles inside a single pump, so a real
    // query cannot hold the frame open the way this StreamController does.
    final neverDefence = StreamController<Defence?>();
    addTearDown(neverDefence.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'p1',
      overrides: [
        defenceProvider('d1').overrideWith((ref) => neverDefence.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading defence…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('commentBody')), findsNothing);
    expect(find.textContaining('Pre-oral'), findsNothing);
  });

  testWidgets(
      'the comments stream loading is shown, not collapsed into absent',
      (tester) async {
    final neverComments = StreamController<List<DefenceComment>>();
    addTearDown(neverComments.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'p1',
      overrides: [
        defenceCommentsProvider('d1')
            .overrideWith((ref) => neverComments.stream),
      ],
    ));
    // The defence stream still has to resolve through the real auth stream
    // and the real fake-firestore query before the comments branch is even
    // reached -- that is its own async gap, so one pump only gets partway.
    // Pumping a few more times (never pumpAndSettle, which would also drain
    // the never-emitting comments stream's non-existent event) lets the
    // defence settle while leaving the comments stream untouched.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading comments…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('commentBody')), findsNothing);
    expect(find.byKey(const Key('commentRow-cm0')), findsNothing);
  });

  testWidgets(
      'the current-user stream loading is shown, not collapsed into absent',
      (tester) async {
    final neverUser = StreamController<AppUser?>();
    addTearDown(neverUser.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'p1',
      overrides: [
        currentUserProvider.overrideWith((ref) => neverUser.stream),
      ],
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading your profile…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('commentBody')), findsNothing);
    expect(find.byKey(const Key('openDefence')), findsNothing);
    expect(find.byKey(const Key('closeDefence')), findsNothing);
  });
}
