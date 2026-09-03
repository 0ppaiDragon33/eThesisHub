import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/notification_providers.dart';

/// Where tapping a notification of this type should land, and which
/// [FacultyMode] the reader needs to be in to land there sensibly (D75).
///
/// `null` mode means "no mode-switch is relevant" — a student-only or
/// role-agnostic destination.
({String route, FacultyMode? mode}) _destinationFor(AppNotification n) {
  switch (n.type) {
    case NotificationType.conformeRequested:
      return (route: '/nominations', mode: null);
    case NotificationType.nominationRecommended:
    case NotificationType.nominationApproved:
    case NotificationType.titleApproved:
    case NotificationType.titleRejected:
      return (route: '/thesis', mode: null);
    case NotificationType.chapterFeedback:
      return (route: '/thesis/chapters', mode: FacultyMode.adviser);
    case NotificationType.defenceComment:
    case NotificationType.defenceScheduled:
      return (route: '/defence/${n.thesisId}', mode: null);
    case NotificationType.evaluationAwaits:
      return (route: '/defence/${n.thesisId}', mode: FacultyMode.panelist);
    case NotificationType.archivePublished:
      return (route: '/archive/${n.thesisId}', mode: null);
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
    final role = ref.watch(currentUserProvider).valueOrNull?.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            key: const Key('markAllRead'),
            tooltip: 'Mark all read',
            icon: const Icon(Icons.done_all),
            onPressed: () => markAllNotificationsRead(ref),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Nothing yet'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final n = items[i];
                return ListTile(
                  leading: Icon(n.read ? Icons.circle_outlined : Icons.circle, size: 10),
                  title: Text(n.message),
                  subtitle: Text('${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year}'),
                  onTap: () async {
                    await markNotificationRead(ref, n.id);
                    final dest = _destinationFor(n);
                    // Switch mode first (D75): a faculty member opening a
                    // panelist-only notification while in Adviser mode must
                    // not land on a screen their current mode hides.
                    if (dest.mode != null && role == UserRole.faculty) {
                      ref.read(facultyModeProvider.notifier).set(dest.mode!);
                    }
                    if (context.mounted) context.push(dest.route);
                  },
                );
              },
            ),
    );
  }
}
