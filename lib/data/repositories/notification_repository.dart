// lib/data/repositories/notification_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/app_notification.dart';

/// One reader's own notification feed, at `notifications/{uid}/items`.
///
/// Every method here takes the `uid` whose subcollection to touch — never
/// resolved internally from auth state — because every call site (the
/// detectors in `notification_providers.dart`) is a self-authored write
/// (D70) and must be explicit about whose feed it is writing into. There
/// is no method that touches another user's `uid`.
class NotificationRepository {
  NotificationRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _items(String uid) => _firestore
      .collection('notifications')
      .doc(uid)
      .collection('items');

  Stream<List<AppNotification>> watchItems(String uid) {
    return _items(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppNotification.fromMap(d.id, {
                  ...d.data(),
                  'createdAt': (d.data()['createdAt'] as Timestamp?)?.toDate(),
                }))
            .toList());
  }

  /// Writes [item] only if no document with its id already exists.
  ///
  /// The read-then-write is deliberate, not an oversight: a plain `set`
  /// would silently resurrect `read: false` on an item the reader already
  /// dismissed, the moment a detector re-runs against the same source
  /// event (which every detector does on every emission of its source
  /// stream, by design -- see `_detect` in `notification_providers.dart`).
  Future<void> upsertIfAbsent(String uid, AppNotification item) async {
    final ref = _items(uid).doc(item.id);
    final existing = await ref.get();
    if (existing.exists) return;
    await ref.set(item.toMap());
  }

  Future<void> markRead(String uid, String itemId) =>
      _items(uid).doc(itemId).update({'read': true});

  Future<void> markAllRead(String uid, List<String> itemIds) async {
    final batch = _firestore.batch();
    for (final id in itemIds) {
      batch.update(_items(uid).doc(id), {'read': true});
    }
    await batch.commit();
  }
}
