import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
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
/// IS the source of truth.
DefenceReadiness readinessOf(List<ThesisChapter> chapters) {
  final approved = {
    for (final c in chapters)
      if (c.status == ChapterStatus.approved) c.id,
  };
  if (ChapterId.finalChapters.every(approved.contains)) {
    return DefenceReadiness.finalReady;
  }
  if (ChapterId.proposalChapters.every(approved.contains)) {
    return DefenceReadiness.proposalReady;
  }
  return DefenceReadiness.notReady;
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
/// its chapters -- in a child widget, [_ReadinessRow], because a dynamic
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
        message: 'Could not load defence readiness.',
      ),
      data: (theses) {
        if (theses.isEmpty) {
          return const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No theses with an approved title yet',
            message: 'Once a group\'s candidate title is approved, its '
                'chapter progress toward a defence appears here.',
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

/// One thesis's row: its title, how many of the five chapters are
/// approved, and the readiness label.
///
/// A separate widget so its `chaptersProvider(thesis.id)` watch has its
/// own loading and error handling. Collapsing that into the parent's data
/// branch would mean a thesis whose chapters are still loading shows zero
/// approved -- the same "0 of 5, not ready" a group that has genuinely
/// approved nothing would show, indistinguishable from it.
class _ReadinessRow extends ConsumerWidget {
  const _ReadinessRow({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider(thesis.id));
    // Coordinator only -- the rules already deny anyone else the write that
    // schedules a defence, but a control that always fails is worse than no
    // control, so it is hidden rather than merely disabled for a dean, who
    // reaches this same list to monitor readiness without scheduling it.
    final isCoordinator =
        ref.watch(currentUserProvider).valueOrNull?.role == UserRole.coordinator;

    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final chapters = chaptersAsync.valueOrNull;
    final approvedCount = chapters
            ?.where((c) => c.status == ChapterStatus.approved)
            .length ??
        0;
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(thesis.workingTitle, style: text.titleMedium),
                    const SizedBox(height: AppTokens.sm),
                    chaptersAsync.when(
                      loading: () => Text('Chapters still loading…',
                          style: text.bodySmall),
                      error: (e, _) => Text(
                          'Could not load this thesis\'s chapters.',
                          style: text.bodySmall),
                      data: (_) => Row(
                        children: [
                          SizedBox(
                            width: 160,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: approvedCount / 5,
                                minHeight: 6,
                                color: Tone.endorsed.color(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTokens.sm),
                          Flexible(
                            child: Text(
                                '$approvedCount of 5 chapters approved',
                                style: text.bodySmall),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.md),
              if (readiness != null)
                ToneBadge(label: _labelFor(readiness), tone: tone, dense: true)
              else if (chaptersAsync.hasError)
                const Icon(Icons.error_outline)
              else
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (isCoordinator) ...[
                const SizedBox(width: AppTokens.sm),
                IconButton(
                  key: Key('schedule-${thesis.id}'),
                  icon: const Icon(Icons.event_available_outlined),
                  tooltip: 'Schedule a defence',
                  onPressed: () =>
                      context.push('/defence/schedule?id=${thesis.id}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
