import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
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
  const DefencesList({
    super.key,
    this.where,
    this.emptyTitle = 'No defences scheduled',
    this.emptyMessage = 'A defence appears here once the Coordinator '
        'schedules one you are part of.',
  });

  /// Which of the reader's defences to show; all of them when null. The
  /// Defences page passes one stage's [DefenceStage.includes].
  final bool Function(Defence)? where;
  final String emptyTitle;
  final String emptyMessage;

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
        final shown = where == null ? defences : defences.where(where!).toList();
        if (shown.isEmpty) {
          return EmptyState(
            key: const Key('noDefences'),
            icon: Icons.forum_outlined,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        final preOral = _sorted(
            shown.where((d) => d.type == DefenceType.preOral).toList());
        final final_ = _sorted(
            shown.where((d) => d.type == DefenceType.final_).toList());
        // A section reads "re-defences" only when EVERY defence in it is
        // one -- a mixed section (the ordinary Defences list, where a
        // pre-oral and its re-defence can both appear) still reads as a
        // plain pre-oral/final section.
        bool allRedefences(List<Defence> ds) =>
            ds.isNotEmpty && ds.every((d) => d.isRedefence);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (preOral.isNotEmpty) ...[
              _SectionHeading(
                  key: const Key('defenceSection-preOral'),
                  label: allRedefences(preOral)
                      ? 'Pre-oral re-defences'
                      : 'Pre-oral defences',
                  count: preOral.length),
              for (final d in preOral) DefenceRow(defence: d),
            ],
            if (final_.isNotEmpty) ...[
              _SectionHeading(
                  key: const Key('defenceSection-final'),
                  label: allRedefences(final_)
                      ? 'Final re-defences'
                      : 'Final defences',
                  count: final_.length),
              for (final d in final_) DefenceRow(defence: d),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SectionRule(
      label,
      trailing: Text('$count', style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class DefenceRow extends ConsumerWidget {
  const DefenceRow({super.key, required this.defence});

  final Defence defence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = defence;
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final thesisAsync = ref.watch(thesisByIdProvider(d.thesisId));
    final cancelled = d.status == DefenceStatus.cancelled;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final completed = d.status == DefenceStatus.completed;
    final isPanelist = uid != null && d.panelUids.contains(uid);
    final isAdviser = uid != null && uid == d.adviserUid;
    // Read non-blockingly, unlike the room screen: a row must render its
    // title, status and Open control the instant the defence arrives, and
    // a profile still in flight simply means the two release-gated
    // affordances appear a frame later rather than the whole row waiting.
    final role = ref.watch(currentUserProvider).valueOrNull?.role;
    final isCoordinator = role == UserRole.coordinator;
    final isDean = role == UserRole.dean;

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

    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final at = d.scheduledAt;

    final buttons = <Widget>[
      // A completed defence's panelist gets the sheet; `push`, not `go`:
      // these are deep screens under the Defences destination.
      if (completed && isPanelist)
        FilledButton(
          key: Key('goToEvaluate-${d.id}'),
          onPressed: () => context.push('/defence/room/${d.id}/evaluate'),
          child: const Text('Evaluate'),
        ),
      // The adviser always; panelists, coordinator and dean once released.
      if (completed &&
          (isAdviser ||
              ((isPanelist || isCoordinator || isDean) &&
                  d.evaluationsReleased)))
        OutlinedButton(
          key: Key('goToGrades-${d.id}'),
          onPressed: () => context.push('/defence/room/${d.id}/grades'),
          child: const Text('Grades'),
        ),
      FilledButton.tonal(
        key: Key('goToDefence-${d.id}'),
        // The group reads the adviser's consolidation, never the raw log.
        onPressed: () => context.push(uid != null && uid == d.leaderUid
            ? '/defence/room/${d.id}/consolidated'
            : '/defence/room/${d.id}'),
        child: const Text('Open'),
      ),
    ];

    final dateBlock = Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
      decoration: BoxDecoration(
        color: cancelled ? p.canvas : p.seal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(at == null ? 'TBC' : Dates.monthShort(at),
              style: text.labelSmall?.copyWith(
                  color: cancelled ? muted : p.seal)),
          Text(at == null ? '—' : '${at.toLocal().day}',
              style: text.headlineSmall?.copyWith(
                  color: cancelled ? muted : p.seal, height: 1.1)),
        ],
      ),
    );

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleText,
          style: text.titleMedium?.copyWith(
            fontStyle: titlePending ? FontStyle.italic : FontStyle.normal,
            color: titlePending || cancelled ? muted : null,
            decoration: cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          [
            d.label,
            at == null
                ? 'Date to be confirmed'
                : '${Dates.weekday(at)} ${DefencesList.formatDateTime(at)}',
            if (d.venue.isNotEmpty) d.venue,
          ].join(', '),
          style: text.bodySmall,
        ),
        const SizedBox(height: AppTokens.xs + 2),
        ToneBadge(
          label: defenceStatusLabel(d.status),
          tone: defenceStatusTone(d.status),
          icon: defenceStatusIcon(d.status),
          dense: true,
        ),
      ],
    );

    return Container(
      key: Key('defenceRow-${d.id}'),
      margin: const EdgeInsets.only(bottom: AppTokens.sm + 2),
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: p.rule),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 560;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dateBlock,
            const SizedBox(width: AppTokens.md),
            Expanded(child: words),
            if (!narrow) ...[
              const SizedBox(width: AppTokens.md),
              Wrap(spacing: AppTokens.sm, children: buttons),
            ],
          ],
        );
        if (!narrow) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row,
            const SizedBox(height: AppTokens.md - 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              children: buttons,
            ),
          ],
        );
      }),
    );
  }
}
