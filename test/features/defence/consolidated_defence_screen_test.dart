import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/consolidated_defence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Seeds a thesis `t1`, a defence `d1` on it with adviser `a1` (Dr. Zamora),
/// panel `[p1, p2]`, leader `l1`, coordinator `c1`, and `users/{uid}`
/// profiles for each role a test signs in as. `status` defaults to
/// `completed` because most of these tests are about consolidation and
/// release, which only make sense once the defence has closed.
Future<FakeFirebaseFirestore> seed({
  String status = 'completed',
  DateTime? consolidatedAt,
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
    if (consolidatedAt != null)
      'consolidatedAt': Timestamp.fromDate(consolidatedAt),
  });
  await db.collection('users').doc('a1').set({
    'fullName': 'Dr. Zamora',
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
  await db.collection('users').doc('l1').set({
    'fullName': 'Leader One',
    'email': 'l1@isufst.edu.ph',
    'role': 'student',
    'active': true,
  });

  for (var i = 0; i < comments.length; i++) {
    final c = comments[i];
    await db.collection('defenses/d1/comments').doc('cm$i').set({
      'authorUid': c['authorUid'],
      'authorName': c['authorName'],
      'authorPosition': c['authorPosition'],
      'body': c['body'],
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 20, 9, i)),
    });
  }
  return db;
}

// Without this override, `FirebaseAuth.instance` throws `[core/no-app]`
// because no app is initialised in a widget test. See
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
      child: MaterialApp(
        // the app shell supplies the Scaffold in the real app.
        home: Scaffold(
          appBar: AppBar(title: const Text('Consolidated comments')),
          body: ConsolidatedDefenceScreen(defenceId: 'd1'),
        ),
      ),
    );

void main() {
  testWidgets('the comments group into one block per commenter',
      (tester) async {
    // Seeded in an order that CONTRADICTS the expected grouping: the
    // panelist's remark sits between the adviser's two, so a screen that
    // merely rendered comments in stream order (without grouping through
    // blocksFor) would show three rows, not two blocks, and would put the
    // adviser's second remark in the wrong place if grouping were deleted.
    final db = await seed(comments: [
      {
        'authorUid': 'a1',
        'authorName': 'Dr. Zamora',
        'authorPosition': 'Adviser',
        'body': 'Tighten chapter two.',
      },
      {
        'authorUid': 'p1',
        'authorName': 'Panelist One',
        'authorPosition': 'Panel Member',
        'body': 'Methodology looks solid.',
      },
      {
        'authorUid': 'a1',
        'authorName': 'Dr. Zamora',
        'authorPosition': 'Adviser',
        'body': 'Add more recent citations.',
      },
    ]);

    // Viewed by a panelist, who -- like the adviser -- already heard every
    // remark live and so is not gated on release the way the leader is.
    await tester.pumpWidget(_wrap(db, uid: 'p2'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('blockFor-a1')), findsOneWidget);
    expect(find.byKey(const Key('blockFor-p1')), findsOneWidget);

    final headers = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .toList();
    expect(headers, contains('[Dr. Zamora — Adviser]'));

    // First-spoken-first: the adviser's block (first comment) must lay out
    // above the panelist's block (second comment).
    final adviserBlock = tester.getTopLeft(find.byKey(const Key('blockFor-a1')));
    final panelistBlock = tester.getTopLeft(find.byKey(const Key('blockFor-p1')));
    expect(adviserBlock.dy, lessThan(panelistBlock.dy));
  });

  testWidgets('only the adviser sees the release control', (tester) async {
    final db = await seed(comments: [
      {
        'authorUid': 'a1',
        'authorName': 'Dr. Zamora',
        'authorPosition': 'Adviser',
        'body': 'Tighten chapter two.',
      },
    ]);

    await tester.pumpWidget(_wrap(db, uid: 'p1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('releaseComments')), findsNothing);

    await tester.pumpWidget(_wrap(db, uid: 'c1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('releaseComments')), findsNothing);

    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('releaseComments')), findsOneWidget);
  });

  testWidgets('release is disabled until the defence is completed',
      (tester) async {
    final db = await seed(status: 'inProgress', comments: [
      {
        'authorUid': 'a1',
        'authorName': 'Dr. Zamora',
        'authorPosition': 'Adviser',
        'body': 'Tighten chapter two.',
      },
    ]);

    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    final button =
        tester.widget<FilledButton>(find.byKey(const Key('releaseComments')));
    expect(button.onPressed, isNull);
    expect(find.byKey(const Key('releaseReason')), findsOneWidget);
  });

  testWidgets('releasing sets consolidatedAt once', (tester) async {
    final db = await seed(status: 'completed', comments: [
      {
        'authorUid': 'a1',
        'authorName': 'Dr. Zamora',
        'authorPosition': 'Adviser',
        'body': 'Tighten chapter two.',
      },
    ]);

    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('releaseComments')));
    await tester.pumpAndSettle();

    final saved = await db.collection('defenses').doc('d1').get();
    expect(saved.data()?['consolidatedAt'], isNotNull);

    // Gone rather than tappable again -- releasing twice must not be
    // possible from this screen.
    expect(find.byKey(const Key('releaseComments')), findsNothing);
  });

  testWidgets('the group sees nothing before release', (tester) async {
    final db = await seed(status: 'completed', comments: [
      {
        'authorUid': 'a1',
        'authorName': 'Dr. Zamora',
        'authorPosition': 'Adviser',
        'body': 'Tighten chapter two.',
      },
    ]);

    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('blockFor-a1')), findsNothing);
    expect(find.byKey(const Key('notReleasedReason')), findsOneWidget);
    expect(find.textContaining('has not released'), findsOneWidget);
  });

  testWidgets('the defence stream loading is shown, not collapsed into absent',
      (tester) async {
    final neverDefence = StreamController<Defence?>();
    addTearDown(neverDefence.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'a1',
      overrides: [
        defenceProvider('d1').overrideWith((ref) => neverDefence.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading defence…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('releaseComments')), findsNothing);
  });

  testWidgets(
      'the comments stream loading is shown, not collapsed into absent',
      (tester) async {
    final neverComments = StreamController<List<DefenceComment>>();
    addTearDown(neverComments.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'a1',
      overrides: [
        defenceCommentsProvider('d1')
            .overrideWith((ref) => neverComments.stream),
      ],
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading comments…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('releaseComments')), findsNothing);
  });

  testWidgets(
      'the current-user stream loading is shown, not collapsed into absent',
      (tester) async {
    final neverUser = StreamController<AppUser?>();
    addTearDown(neverUser.close);

    await tester.pumpWidget(_wrap(
      await seed(),
      uid: 'a1',
      overrides: [
        currentUserProvider.overrideWith((ref) => neverUser.stream),
      ],
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading your profile…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('releaseComments')), findsNothing);
  });

  testWidgets(
      'an unreleased leader sees the not-released reason even when the '
      'comments stream errors with permission-denied', (tester) async {
    // FIX 3: `firestore.rules` denies a leader ANY read of `comments`
    // until `consolidatedAt` exists, so in production this is exactly what
    // `commentsAsync` does for an unreleased leader -- `fake_cloud_firestore`
    // enforces no rules, so every other test in this file is green
    // regardless of branch order. Overriding the stream with the real
    // failure shape is what makes this test model production instead of
    // the fake, and it is what catches the bug the final review found: the
    // old branch order let this error reach `commentsAsync.hasError` FIRST
    // and render "Could not load the comment log." instead of
    // `notReleasedReason`.
    final db = await seed(status: 'completed', comments: [
      {
        'authorUid': 'a1',
        'authorName': 'Dr. Zamora',
        'authorPosition': 'Adviser',
        'body': 'Tighten chapter two.',
      },
    ]);

    await tester.pumpWidget(_wrap(
      db,
      uid: 'l1',
      overrides: [
        defenceCommentsProvider('d1').overrideWith((ref) => Stream.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            )),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notReleasedReason')), findsOneWidget);
    expect(find.text('Could not load the comment log.'), findsNothing);
    expect(find.byKey(const Key('blockFor-a1')), findsNothing);
  });
}
