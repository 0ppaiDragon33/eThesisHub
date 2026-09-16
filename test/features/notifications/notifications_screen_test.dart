import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/notifications/notifications_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<void> pump(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required String uid,
}) async {
  final mockUser = MockUser(uid: uid, isEmailVerified: true, email: 'reader@isufst.edu.ph');
  final auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: NotificationsScreen()),
          ),
          GoRoute(path: '/thesis', builder: (_, _) => const Scaffold(body: Text('My thesis'))),
          // Registered in the same order the real router uses: the
          // '/defence/room/...' shapes before the ':thesisId' catch-all.
          GoRoute(
            path: '/defence/room/:defenceId',
            builder: (_, s) => Scaffold(
                body: Text('Defence room ${s.pathParameters['defenceId']}')),
          ),
          GoRoute(
            path: '/defence/room/:defenceId/evaluate',
            builder: (_, s) => Scaffold(
                body: Text('Evaluate ${s.pathParameters['defenceId']}')),
          ),
          GoRoute(
            path: '/defences',
            builder: (_, _) => const Scaffold(body: Text('Defences list')),
          ),
          // Present so a test can prove we do NOT land here: this is M1b's
          // title defence screen, keyed by a THESIS id.
          GoRoute(
            path: '/defence/:thesisId',
            builder: (_, s) => Scaffold(
                body: Text('Title defence ${s.pathParameters['thesisId']}')),
          ),
        ]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<FakeFirebaseFirestore> firestoreWith(List<Map<String, dynamic>> items, String uid) async {
  final firestore = FakeFirebaseFirestore();
  for (final item in items) {
    await firestore
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(item['id'] as String)
        .set(item);
  }
  return firestore;
}

void main() {
  testWidgets('lists every item, newest first, unread visually distinct', (tester) async {
    final firestore = await firestoreWith([
      {
        'id': 'a',
        'type': 'archivePublished',
        'thesisId': 't1',
        'message': 'Older, already read',
        'read': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      },
      {
        'id': 'b',
        'type': 'defenceComment',
        'thesisId': 't1',
        'message': 'Newer, unread',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
      },
    ], 'u1');

    await pump(tester, firestore: firestore, uid: 'u1');

    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(
      tester.widget<ListTile>(tiles.at(0)).title,
      isA<Text>().having((t) => t.data, 'text', 'Newer, unread'),
    );
  });

  testWidgets('an empty feed shows an empty state, not a blank screen', (tester) async {
    final firestore = await firestoreWith([], 'u1');
    await pump(tester, firestore: firestore, uid: 'u1');
    expect(find.text('Nothing yet'), findsOneWidget);
  });

  testWidgets('tapping an item marks it read', (tester) async {
    final firestore = await firestoreWith([
      {
        'id': 'a',
        'type': 'archivePublished',
        'thesisId': 't1',
        'message': 'Tap me',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      },
    ], 'u1');

    await pump(tester, firestore: firestore, uid: 'u1');
    await tester.tap(find.text('Tap me'));
    await tester.pumpAndSettle();

    final doc = await firestore.collection('notifications').doc('u1').collection('items').doc('a').get();
    expect(doc.data()!['read'], isTrue);
  });

  testWidgets('mark all read clears every unread item', (tester) async {
    final firestore = await firestoreWith([
      {
        'id': 'a',
        'type': 'archivePublished',
        'thesisId': 't1',
        'message': 'One',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      },
      {
        'id': 'b',
        'type': 'defenceComment',
        'thesisId': 't1',
        'message': 'Two',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
      },
    ], 'u1');

    await pump(tester, firestore: firestore, uid: 'u1');
    await tester.tap(find.byKey(const Key('markAllRead')));
    await tester.pumpAndSettle();

    final items = await firestore.collection('notifications').doc('u1').collection('items').get();
    expect(items.docs.every((d) => d.data()['read'] == true), isTrue);
  });
  group('defence notifications address the defence, not the thesis', () {
    // A defence notification used to route to '/defence/{thesisId}' --
    // M1b's TitleDefenceScreen. The reader wanted the defence they were
    // told about and landed on a screen about candidate titles instead.
    // The item now carries the defence's own id.

    testWidgets('a defence comment opens that defence room', (tester) async {
      final firestore = await firestoreWith([
        {
          'id': 'c1',
          'type': 'defenceComment',
          'thesisId': 't1',
          'defenceId': 'd1',
          'message': 'Dr. Cruz commented on your defence.',
          'read': false,
          'createdAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
        },
      ], 'u1');

      await pump(tester, firestore: firestore, uid: 'u1');
      await tester.tap(find.text('Dr. Cruz commented on your defence.'));
      await tester.pumpAndSettle();

      expect(find.text('Defence room d1'), findsOneWidget);
      expect(find.text('Title defence t1'), findsNothing);
    });

    testWidgets('a scheduled defence opens that defence room', (tester) async {
      final firestore = await firestoreWith([
        {
          'id': 's1',
          'type': 'defenceScheduled',
          'thesisId': 't1',
          'defenceId': 'd2',
          'message': 'Your defence is scheduled.',
          'read': false,
          'createdAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
        },
      ], 'u1');

      await pump(tester, firestore: firestore, uid: 'u1');
      await tester.tap(find.text('Your defence is scheduled.'));
      await tester.pumpAndSettle();

      expect(find.text('Defence room d2'), findsOneWidget);
    });

    testWidgets('an owed evaluation opens the Form 5c sheet itself',
        (tester) async {
      final firestore = await firestoreWith([
        {
          'id': 'e1',
          'type': 'evaluationAwaits',
          'thesisId': 't1',
          'defenceId': 'd3',
          'message': 'A defence is waiting on your Form 5c.',
          'read': false,
          'createdAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
        },
      ], 'u1');

      await pump(tester, firestore: firestore, uid: 'u1');
      await tester.tap(find.text('A defence is waiting on your Form 5c.'));
      await tester.pumpAndSettle();

      expect(find.text('Evaluate d3'), findsOneWidget);
    });

    testWidgets(
        'an item written before defenceId existed falls back to the '
        'defences list, never to the title defence screen', (tester) async {
      // Items already in real users' feeds have no `defenceId` key. They
      // must still go somewhere sensible -- the list the reader can find
      // the defence in -- rather than a screen about something else.
      final firestore = await firestoreWith([
        {
          'id': 'legacy',
          'type': 'defenceComment',
          'thesisId': 't1',
          'message': 'An older comment notification.',
          'read': false,
          'createdAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
        },
      ], 'u1');

      await pump(tester, firestore: firestore, uid: 'u1');
      await tester.tap(find.text('An older comment notification.'));
      await tester.pumpAndSettle();

      expect(find.text('Defences list'), findsOneWidget);
      expect(find.text('Title defence t1'), findsNothing);
    });
  });
}
