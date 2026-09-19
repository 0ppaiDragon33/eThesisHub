// test/data/repositories/notification_repository_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/repositories/notification_repository.dart';

AppNotification item({
  String id = 'archivePublished_t1',
  bool read = false,
  DateTime? createdAt,
}) {
  return AppNotification(
    id: id,
    type: NotificationType.archivePublished,
    thesisId: 't1',
    message: 'Your thesis was published to the archive.',
    read: read,
    createdAt: createdAt ?? DateTime(2026, 9, 3),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late NotificationRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = NotificationRepository(firestore);
  });

  group('upsertIfAbsent', () {
    test('writes a new item', () async {
      await repo.upsertIfAbsent('u1', item());

      final snap = await firestore
          .collection('notifications')
          .doc('u1')
          .collection('items')
          .doc('archivePublished_t1')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['message'], 'Your thesis was published to the archive.');
    });

    test('never overwrites an existing item -- read state survives redetection', () async {
      await repo.upsertIfAbsent('u1', item());
      await repo.markRead('u1', 'archivePublished_t1');

      // Redetection fires again with the same deterministic id (D71).
      await repo.upsertIfAbsent('u1', item());

      final items = await repo.watchItems('u1').first;
      expect(items.single.read, isTrue);
    });
  });

  group('watchItems', () {
    test('newest first', () async {
      await repo.upsertIfAbsent('u1', item(id: 'a', createdAt: DateTime(2026, 1, 1)));
      await repo.upsertIfAbsent('u1', item(id: 'b', createdAt: DateTime(2026, 6, 1)));

      final items = await repo.watchItems('u1').first;
      expect(items.map((i) => i.id).toList(), ['b', 'a']);
    });

    test("one user's items never appear in another's watch", () async {
      await repo.upsertIfAbsent('u1', item());
      final other = await repo.watchItems('u2').first;
      expect(other, isEmpty);
    });

    test('streams at most the feed limit, newest first', () async {
      // The feed used to re-stream every notification ever received. Seed
      // past the cap and confirm the oldest fall away rather than being read
      // on every listen.
      for (var i = 0; i < kNotificationFeedLimit + 10; i++) {
        await repo.upsertIfAbsent(
          'u1',
          item(id: 'n$i', createdAt: DateTime(2026, 1, 1).add(Duration(days: i))),
        );
      }

      final items = await repo.watchItems('u1').first;
      expect(items, hasLength(kNotificationFeedLimit));
      // Newest kept: the last-seeded id is the most recent.
      expect(items.first.id, 'n${kNotificationFeedLimit + 9}');
    });
  });

  group('markAllRead', () {
    test('marks every listed item read in one batch', () async {
      await repo.upsertIfAbsent('u1', item(id: 'a'));
      await repo.upsertIfAbsent('u1', item(id: 'b'));

      await repo.markAllRead('u1', ['a', 'b']);

      final items = await repo.watchItems('u1').first;
      expect(items.every((i) => i.read), isTrue);
    });
  });
}
