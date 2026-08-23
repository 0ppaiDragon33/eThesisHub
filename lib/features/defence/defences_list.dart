import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Every defence the signed-in user belongs to, soonest first.
///
/// One widget shared by all four dashboards rather than one query per
/// screen: [myDefencesProvider] already resolves the right query (or, for
/// faculty, the merge of two) for whichever role is signed in, so the
/// widget itself needs no branching on role at all.
class DefencesList extends ConsumerWidget {
  const DefencesList({super.key});

  static String _statusLabel(DefenceStatus status) => switch (status) {
        DefenceStatus.scheduled => 'Scheduled',
        DefenceStatus.inProgress => 'In progress',
        DefenceStatus.completed => 'Completed',
      };

  static Color _statusColor(DefenceStatus status, Brightness brightness) {
    final light = brightness == Brightness.light;
    return switch (status) {
      DefenceStatus.scheduled =>
        light ? AppTokens.awaiting : AppTokens.awaitingDark,
      DefenceStatus.inProgress =>
        light ? AppTokens.endorsed : AppTokens.endorsedDark,
      DefenceStatus.completed =>
        light ? AppTokens.inkMuted : AppTokens.inkMutedDark,
    };
  }

  /// Same shape as the picker copy in `schedule_defence_screen.dart`, kept
  /// local rather than shared: this is the only other screen that renders a
  /// [DateTime] to a person, and pulling in `intl` for one format string
  /// across two files would be the heavier dependency.
  static String _formatDateTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defencesAsync = ref.watch(myDefencesProvider);
    final brightness = Theme.of(context).brightness;

    // Its own loading/error/empty branches, kept apart from whatever else
    // shares the page: a schedule that is merely still connecting must
    // never render as "no defences" -- see the loading test, which pumps a
    // never-emitting stream once (no pumpAndSettle) specifically to catch
    // this collapsing back in.
    return defencesAsync.when(
      loading: () => const LoadingState(label: 'Loading your defences…'),
      error: (e, _) => ErrorState(
        error: e,
        message: 'Could not load your defences.',
      ),
      data: (defences) {
        if (defences.isEmpty) {
          return const EmptyState(
            key: Key('noDefences'),
            icon: Icons.forum_outlined,
            title: 'No defences scheduled',
            message: 'A defence appears here once the Coordinator schedules '
                'one you are part of.',
          );
        }
        return Column(
          children: [
            for (final d in defences)
              Card(
                key: Key('defenceRow-${d.id}'),
                child: ListTile(
                  title: Text(d.type.label),
                  subtitle: Text(
                    '${d.scheduledAt != null ? _formatDateTime(d.scheduledAt!) : 'Date to be confirmed'} '
                    '· ${d.venue}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.md - AppTokens.xs,
                          vertical: AppTokens.xs + 1,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(d.status, brightness)
                              .withValues(alpha: 0.10),
                          border: Border.all(
                            color: _statusColor(d.status, brightness)
                                .withValues(alpha: 0.45),
                          ),
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusSm),
                        ),
                        child: Text(
                          _statusLabel(d.status),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: _statusColor(d.status, brightness)),
                        ),
                      ),
                      const SizedBox(width: AppTokens.sm),
                      FilledButton(
                        key: Key('goToDefence-${d.id}'),
                        onPressed: () => context.go('/defence/room/${d.id}'),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
