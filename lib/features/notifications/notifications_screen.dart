import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/notification_providers.dart';

/// Where tapping a notification of this type should land, and which
/// [FacultyMode] the reader needs to be in to land there sensibly (D75).
///
/// `null` mode means "no mode-switch is relevant".
({String route, FacultyMode? mode}) notificationDestination(
    AppNotification n) {
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
    // A defence is addressed by its OWN id, through '/defence/room/...'.
    // '/defence/{thesisId}' is the title defence screen — a different
    // screen — so an item with no `defenceId` goes to the defences list.
    case NotificationType.defenceComment:
    case NotificationType.defenceScheduled:
      final id = n.defenceId;
      return (
        route: id == null ? '/defences?stage=preOral' : '/defence/room/$id',
        mode: null,
      );
    case NotificationType.evaluationAwaits:
      final id = n.defenceId;
      return (
        route: id == null
            ? '/defences?stage=preOral'
            : '/defence/room/$id/evaluate',
        mode: FacultyMode.panelist,
      );
    case NotificationType.archivePublished:
      return (route: '/archive/${n.thesisId}', mode: null);
  }
}

/// The icon and tone a notification type is drawn with.
({IconData icon, Tone tone}) notificationLook(NotificationType type) =>
    switch (type) {
      NotificationType.conformeRequested =>
        (icon: Icons.how_to_reg_outlined, tone: Tone.act),
      NotificationType.nominationRecommended =>
        (icon: Icons.inventory_2_outlined, tone: Tone.endorsed),
      NotificationType.nominationApproved =>
        (icon: Icons.verified_outlined, tone: Tone.endorsed),
      NotificationType.titleApproved =>
        (icon: Icons.task_alt_rounded, tone: Tone.endorsed),
      NotificationType.titleRejected =>
        (icon: Icons.undo_rounded, tone: Tone.returned),
      NotificationType.chapterFeedback =>
        (icon: Icons.rate_review_outlined, tone: Tone.act),
      NotificationType.defenceComment =>
        (icon: Icons.chat_bubble_outline_rounded, tone: Tone.neutral),
      NotificationType.defenceScheduled =>
        (icon: Icons.event_outlined, tone: Tone.awaiting),
      NotificationType.evaluationAwaits =>
        (icon: Icons.fact_check_outlined, tone: Tone.act),
      NotificationType.archivePublished =>
        (icon: Icons.local_library_outlined, tone: Tone.endorsed),
    };

/// Marks [n] read, switches faculty mode when the target needs it, then
/// opens the target.
Future<void> openNotification(
  BuildContext context,
  WidgetRef ref,
  AppNotification n,
) async {
  final role = ref.read(currentUserProvider).valueOrNull?.role;
  await markNotificationRead(ref, n.id);
  final dest = notificationDestination(n);
  // Switch mode first (D75): a faculty member opening a panelist-only
  // notification while in Adviser mode must not land on a screen their
  // current mode hides.
  if (dest.mode != null && role == UserRole.faculty) {
    ref.read(facultyModeProvider.notifier).set(dest.mode!);
  }
  if (context.mounted) context.push(dest.route);
}

enum _Filter { all, unread }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider);

    return PageShell(
      key: const Key('notificationsScreen'),
      title: 'Notifications',
      subtitle: unread == 0
          ? 'You are up to date.'
          : '$unread unread. Opening one takes you to what it is about.',
      actions: [
        TextButton.icon(
          key: const Key('markAllRead'),
          onPressed: unread == 0 ? null : () => markAllNotificationsRead(ref),
          icon: const Icon(Icons.done_all_rounded, size: 18),
          label: const Text('Mark all read'),
        ),
      ],
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<_Filter>(
            key: const Key('notificationFilter'),
            segments: [
              const ButtonSegment(value: _Filter.all, label: Text('All')),
              ButtonSegment(
                value: _Filter.unread,
                label: Text(unread == 0 ? 'Unread' : 'Unread ($unread)'),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
        ),
        const Gap.md(),
        async.when(
          loading: () => const LoadingState(label: 'Loading notifications…'),
          error: (e, _) => ErrorState(
            error: e,
            message: 'Could not load your notifications.',
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (all) {
            final items = _filter == _Filter.all
                ? all
                : all.where((n) => !n.read).toList();
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.notifications_none_rounded,
                title: _filter == _Filter.all
                    ? 'No notifications yet'
                    : 'No unread notifications',
                message: 'Decisions on your nominations, titles, chapters '
                    'and defences are posted here as they happen.',
              );
            }
            return FadeIn(child: NotificationGroups(items: items));
          },
        ),
      ],
    );
  }
}

/// Notifications grouped under Today / This week / Earlier.
class NotificationGroups extends StatelessWidget {
  const NotificationGroups({super.key, required this.items});

  final List<AppNotification> items;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));

    String bucket(AppNotification n) {
      final l = n.createdAt.toLocal();
      final d = DateTime(l.year, l.month, l.day);
      if (!d.isBefore(today)) return 'Today';
      if (!d.isBefore(weekStart)) return 'This week';
      return 'Earlier';
    }

    final groups = <String, List<AppNotification>>{};
    for (final n in items) {
      groups.putIfAbsent(bucket(n), () => []).add(n);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          Panel(
            title: entry.key,
            flush: true,
            child: Column(
              children: [
                for (final n in entry.value) NotificationTile(n: n),
              ],
            ),
          ),
          const Gap.md(),
        ],
      ],
    );
  }
}

/// One notification row: type icon, message, time, unread marker.
class NotificationTile extends ConsumerWidget {
  const NotificationTile({super.key, required this.n, this.compact = false});

  final AppNotification n;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final look = notificationLook(n.type);
    final c = look.tone.color(context);

    return Semantics(
      label: n.read ? null : 'Unread',
      child: Material(
        color: n.read ? Colors.transparent : p.seal.withValues(alpha: 0.04),
        child: InkWell(
          key: Key('notification-${n.id}'),
          onTap: () => openNotification(context, ref, n),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppTokens.md : AppTokens.lg - 4,
              vertical: AppTokens.md - 4,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.rule)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(look.icon, size: 18, color: c),
                ),
                const SizedBox(width: AppTokens.md - 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.message,
                        maxLines: compact ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight:
                              n.read ? FontWeight.w400 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(Dates.relative(n.createdAt), style: text.bodySmall),
                    ],
                  ),
                ),
                if (!n.read)
                  Padding(
                    padding: const EdgeInsets.only(left: AppTokens.sm, top: 6),
                    child: Container(
                      key: const Key('unreadDot'),
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: p.seal, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The latest few notifications, for a dashboard side column.
class RecentNotificationsPanel extends ConsumerWidget {
  const RecentNotificationsPanel({super.key, this.limit = 4});

  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    return Panel(
      title: 'Recent updates',
      icon: Icons.notifications_none_rounded,
      flush: true,
      trailing: TextButton(
        onPressed: () => context.push('/notifications'),
        child: const Text('View all'),
      ),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppTokens.md),
          child: LoadingState(),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: ErrorState(error: e, message: 'Could not load updates.'),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppTokens.lg - 4),
              child: Text(
                'Nothing yet. Decisions and schedule changes will appear '
                'here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          return Column(
            children: [
              for (final n in items.take(limit))
                NotificationTile(n: n, compact: true),
            ],
          );
        },
      ),
    );
  }
}
