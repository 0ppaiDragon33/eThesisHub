import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

enum DefenceReadiness { notReady, proposalReady, finalReady }

/// Computed from the chapters themselves, never stored.
///
/// A stored `proposalReady` flag would have to be written by the adviser's
/// approval, and the rules cannot verify it: validating it means reading
/// the chapter documents, and in a batch those still evaluate against
/// their PRE-batch state, so the very chapter being approved still reads
/// as unapproved. The flag would be forgeable. This cannot be, because it
/// is the source of truth.
DefenceReadiness readinessOf(List<ThesisChapter> chapters) {
  final approved = {
    for (final c in chapters)
      if (c.status == ChapterStatus.approved) c.id,
  };
  // An approved manuscript is the unit now: Chapters I-III before the
  // pre-oral, I-V before the final. A thesis from before manuscripts has
  // its chapters as separate records instead, and those still count.
  if (approved.contains(ChapterId.manuscriptFinal) ||
      ChapterId.finalChapters.every(approved.contains)) {
    return DefenceReadiness.finalReady;
  }
  if (approved.contains(ChapterId.manuscriptProposal) ||
      ChapterId.proposalChapters.every(approved.contains)) {
    return DefenceReadiness.proposalReady;
  }
  return DefenceReadiness.notReady;
}

/// One line saying where a thesis's manuscript stands, for a readiness
/// row or the scheduling screen. Read from the same records as
/// [readinessOf], so the two cannot disagree.
String manuscriptSummary(List<ThesisChapter> chapters) {
  switch (readinessOf(chapters)) {
    case DefenceReadiness.finalReady:
      return 'Chapters I–V approved';
    case DefenceReadiness.proposalReady:
      return 'Chapters I–III approved';
    case DefenceReadiness.notReady:
      // The manuscript the group is on, if any: the full one once it has
      // been started, else the proposal one.
      final byId = {for (final c in chapters) c.id: c};
      final c = byId[ChapterId.manuscriptFinal] ??
          byId[ChapterId.manuscriptProposal];
      if (c == null) {
        return chapters.any((c) => !c.id.isManuscript)
            ? 'Chapters not all approved'
            : 'No manuscript uploaded yet';
      }
      return '${c.id.label}: ${ChapterStatusWords.labelFor(c.status)}';
  }
}

/// A label for [DefenceReadiness], for the row's trailing text.
String _labelFor(DefenceReadiness r) => switch (r) {
      DefenceReadiness.notReady => 'Not ready',
      DefenceReadiness.proposalReady => 'Ready for pre-oral',
      DefenceReadiness.finalReady => 'Ready for final',
    };

/// Which theses with an approved title have become ready for a defence,
/// for the dean and coordinator.
///
/// Watches every thesis at [ThesisStatus.titleApproved] and, per thesis,
/// its chapters: in a child widget, [_ReadinessRow], because a dynamic
/// number of `chaptersProvider` family instances cannot be looped over
/// with `ref.watch` inside this single build. Same shape as
/// `_DefencesList` in faculty_dashboard.dart.
class DefenceReadinessList extends ConsumerWidget {
  const DefenceReadinessList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesesAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.titleApproved));

    return thesesAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        message: 'Could not load defense readiness.',
      ),
      data: (theses) {
        if (theses.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No theses with an approved title yet',
            message: 'Groups appear here once their title is approved.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final thesis in theses) ...[
              _ReadinessRow(thesis: thesis),
              const SizedBox(height: AppTokens.sm + 2),
            ],
          ],
        );
      },
    );
  }
}

/// One thesis's row: its title, where its manuscript stands, and the
/// readiness label.
///
/// A separate widget so its `chaptersProvider(thesis.id)` watch has its
/// own loading and error handling. Collapsing that into the parent's data
/// branch would mean a thesis whose chapters are still loading shows no
/// manuscript: the same "nothing uploaded, not ready" a group that has
/// genuinely uploaded nothing would show, indistinguishable from it.
class _ReadinessRow extends ConsumerWidget {
  const _ReadinessRow({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider(thesis.id));
    // Coordinator only: the rules already deny anyone else the write that
    // schedules a defence, but a control that always fails is worse than no
    // control, so it is hidden rather than merely disabled for a dean, who
    // reaches this same list to monitor readiness without scheduling it.
    final isCoordinator =
        ref.watch(currentUserProvider).valueOrNull?.role == UserRole.coordinator;

    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final chapters = chaptersAsync.valueOrNull;
    final readiness = chapters == null ? null : readinessOf(chapters);
    final tone = switch (readiness) {
      DefenceReadiness.finalReady ||
      DefenceReadiness.proposalReady =>
        Tone.endorsed,
      DefenceReadiness.notReady => Tone.awaiting,
      null => Tone.neutral,
    };

    return Material(
      color: p.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: BorderSide(color: p.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('readiness-${thesis.id}'),
        onTap: () => context.push('/thesis/chapters?id=${thesis.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          // Stacked, never side by side: the title, the bar and the status
          // each get the card's full width. The old layout put a fixed
          // 160-wide bar, its caption, the badge and the schedule button
          // in one row; on a phone the caption was left with almost no
          // width and wrapped one letter per line.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      // Keeps the title level with the button's centre when
                      // the button is shown, and flush when it is not.
                      padding: EdgeInsets.only(
                          top: isCoordinator ? AppTokens.sm : 0),
                      child: Text(thesis.workingTitle,
                          style: text.titleMedium),
                    ),
                  ),
                  if (isCoordinator) ...[
                    const SizedBox(width: AppTokens.sm),
                    IconButton(
                      key: Key('schedule-${thesis.id}'),
                      icon: const Icon(Icons.event_available_outlined),
                      tooltip: 'Schedule a defense',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          context.push('/defence/schedule?id=${thesis.id}'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppTokens.sm),
              chaptersAsync.when(
                loading: () =>
                    Text('Chapters still loading…', style: text.bodySmall),
                error: (e, _) => Row(
                  children: [
                    const Icon(Icons.error_outline, size: 18),
                    const SizedBox(width: AppTokens.sm),
                    Expanded(
                      child: Text('Could not load this thesis\'s chapters.',
                          style: text.bodySmall),
                    ),
                  ],
                ),
                // Where the manuscript stands, not a count of chapters: a
                // group uploads one manuscript. A Wrap so the badge drops
                // under the caption when the two do not fit on one line.
                data: (list) => Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppTokens.sm,
                  runSpacing: AppTokens.xs + 2,
                  children: [
                    Text(manuscriptSummary(list), style: text.bodySmall),
                    if (readiness != null)
                      ToneBadge(
                          label: _labelFor(readiness),
                          tone: tone,
                          dense: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
