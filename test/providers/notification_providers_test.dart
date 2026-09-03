import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/notification_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

void main() {
  Future<ProviderContainer> containerFor(String uid) async {
    final mockUser = MockUser(uid: uid, isEmailVerified: true, email: 'test@example.com');
    final auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc('archivePublished_t1')
        .set({
      'type': 'archivePublished',
      'thesisId': 't1',
      'message': 'Your thesis was published.',
      'read': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 3)),
    });

    final container = ProviderContainer(overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(firestore),
      signedInUidProvider.overrideWithValue(uid),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('notificationsProvider streams the signed-in user\'s own items', () async {
    final container = await containerFor('u1');
    final items = await container.read(notificationsProvider.future);
    expect(items, hasLength(1));
    expect(items.single.thesisId, 't1');
  });

  test('unreadNotificationCountProvider counts only unread items', () async {
    final container = await containerFor('u1');
    await container.read(notificationsProvider.future);
    expect(container.read(unreadNotificationCountProvider), 1);
  });

  test('markNotificationRead flips one item and the count drops', () async {
    final container = await containerFor('u1');
    await container.read(notificationsProvider.future);

    await markNotificationRead(container, 'archivePublished_t1');
    final items = await container.read(notificationsProvider.future);

    expect(items.single.read, isTrue);
  });

  test('markAllNotificationsRead flips every item at once', () async {
    final container = await containerFor('u1');
    final repo = container.read(notificationRepositoryProvider);
    await repo.upsertIfAbsent(
      'u1',
      (await container.read(notificationsProvider.future)).first.copyWith(),
    );

    await markAllNotificationsRead(container);
    final items = await container.read(notificationsProvider.future);

    expect(items.every((i) => i.read), isTrue);
  });
}
