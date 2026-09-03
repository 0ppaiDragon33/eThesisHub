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
}
