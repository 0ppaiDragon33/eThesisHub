import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defence_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Every defence the signed-in user belongs to, soonest first, grouped by
/// [DefenceType].
///
/// One widget shared by all four dashboards rather than one query per
/// screen: [myDefencesProvider] already resolves the right query (or, for
/// faculty, the merge of two) for whichever role is signed in, so the
/// widget itself needs no branching on role at all.
class DefencesList extends ConsumerWidget {
  const DefencesList({super.key});

  /// Same shape as the picker copy in `schedule_defence_screen.dart`, kept
  /// local rather than shared: this is the only other screen that renders a
  /// [DateTime] to a person, and pulling in `intl` for one format string
  /// across two files would be the heavier dependency.
  static String formatDateTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} $hour:$minute $period';
  }

  /// Soonest-first within a section. A null [Defence.scheduledAt] ("Date to
  /// be confirmed") sorts to the end -- it has no date to compare and does
  /// not belong ahead of one that does.
  static List<Defence> _sorted(List<Defence> defences) {
    final sorted = [...defences];
    sorted.sort((a, b) {
      final at = a.scheduledAt;
      final bt = b.scheduledAt;
      if (at == null && bt == null) return a.id.compareTo(b.id);
      if (at == null) return 1;
      if (bt == null) return -1;
      final byTime = at.compareTo(bt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defencesAsync = ref.watch(myDefencesProvider);

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
        final preOral = _sorted(
            defences.where((d) => d.type == DefenceType.preOral).toList());
        final final_ = _sorted(
            defences.where((d) => d.type == DefenceType.final_).toList());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (preOral.isNotEmpty) ...[
              _SectionHeading(
                  key: const Key('defenceSection-preOral'), label: 'Pre-oral'),
              for (final d in preOral) DefenceRow(defence: d),
            ],
            if (final_.isNotEmpty) ...[
              if (preOral.isNotEmpty) const SizedBox(height: AppTokens.lg),
              _SectionHeading(
                  key: const Key('defenceSection-final'), label: 'Final'),
              for (final d in final_) DefenceRow(defence: d),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// One defence, as a [Card]. Shared by [DefencesList] and the day panel in
/// the calendar view, so the two presentations of the same dataset cannot
/// drift apart on what a row shows.
class DefenceRow extends ConsumerWidget {
  const DefenceRow({super.key, required this.defence});

  final Defence defence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = defence;
    final brightness = Theme.of(context).brightness;
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final thesisAsync = ref.watch(thesisByIdProvider(d.thesisId));
    final cancelled = d.status == DefenceStatus.cancelled;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    // A blank string and a real title are visually identical, so a title
    // still in flight must read as "pending", not as nothing at all.
    final titleText = thesisAsync.when(
      loading: () => 'Loading title…',
      error: (_, _) => 'Title unavailable',
      data: (thesis) {
        final t = thesis?.workingTitle ?? '';
        return t.isEmpty ? 'Untitled thesis' : t;
      },
    );
    final titlePending = thesisAsync.isLoading;

    return Card(
      key: Key('defenceRow-${d.id}'),
      child: ListTile(
        title: Text(
          titleText,
          style: TextStyle(
            fontStyle: titlePending ? FontStyle.italic : FontStyle.normal,
            color: titlePending ? muted : (cancelled ? muted : null),
            decoration: cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${d.type.label} · '
          '${d.scheduledAt != null ? DefencesList.formatDateTime(d.scheduledAt!) : 'Date to be confirmed'} '
          '· ${d.venue}',
          style: cancelled ? TextStyle(color: muted) : null,
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
                color: defenceStatusColor(d.status, brightness)
                    .withValues(alpha: 0.10),
                border: Border.all(
                  color: defenceStatusColor(d.status, brightness)
                      .withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Text(
                defenceStatusLabel(d.status),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: defenceStatusColor(d.status, brightness)),
              ),
            ),
            const SizedBox(width: AppTokens.sm),
            FilledButton(
              key: Key('goToDefence-${d.id}'),
              // The group reads the adviser's consolidation, never the raw
              // live log -- M3-2 forbids it, because the log may hold
              // half-finished remarks and ones the panel withdrew.
              // DefenceRoomScreen refuses a leader outright too, so this is
              // belt-and-suspenders, but sending the leader straight to the
              // door they are actually meant to use is the honest UX.
              onPressed: () => context.push(
                  uid != null && uid == d.leaderUid
                      ? '/defence/room/${d.id}/consolidated'
                      : '/defence/room/${d.id}'),
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}
