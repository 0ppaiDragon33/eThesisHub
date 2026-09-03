import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/providers/notification_providers.dart';

/// The bell in the app shell's top bar. Zero unread renders no badge at
/// all -- not a badge reading "0" -- the same "0 is indistinguishable from
/// absent" discipline this project already applies to loading states
/// elsewhere (spec §5).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      key: const Key('notificationBell'),
      tooltip: 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        key: unread > 0 ? const Key('notificationBellBadge') : null,
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
