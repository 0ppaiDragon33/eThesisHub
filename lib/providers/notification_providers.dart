import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/repositories/notification_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(firestoreProvider)),
);

/// The signed-in reader's own feed, newest first.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watchItems(uid);
});

/// Zero when there is nothing unread OR the feed has not resolved yet --
/// the badge renders no chip at all for zero (D — see spec §5, "no badge
/// beats a badge reading zero"), so loading and empty share the same
/// visible result on purpose. A distinct loading state has no UI here to
/// serve; this provider exists to answer exactly one question.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return items.where((i) => !i.read).length;
});

/// Marks a single notification as read. Accepts both `Ref` (from `WidgetRef` in UI)
/// and `ProviderContainer` (from tests), though Dart's type system requires `dynamic`
/// due to ProviderContainer not explicitly implementing the `Ref` interface despite
/// having compatible methods.
Future<void> markNotificationRead(dynamic ref, String itemId) async {
  final uid = ref.read(signedInUidProvider);
  if (uid == null) return;
  await ref.read(notificationRepositoryProvider).markRead(uid, itemId);
}

/// Marks all notifications as read. See [markNotificationRead] for type annotation note.
Future<void> markAllNotificationsRead(dynamic ref) async {
  final uid = ref.read(signedInUidProvider);
  if (uid == null) return;
  final items = await ref.read(notificationsProvider.future);
  final unreadIds = <String>[for (final i in items) if (!i.read) i.id];
  if (unreadIds.isEmpty) return;
  await ref.read(notificationRepositoryProvider).markAllRead(uid, unreadIds);
}
