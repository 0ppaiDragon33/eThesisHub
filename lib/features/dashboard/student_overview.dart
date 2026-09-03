import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';
import 'package:ethesishub/core/widgets/stat_tile_grid.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/progress_rail.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Where a student lands: a greeting, what needs them, where the thesis
/// stands, and the four figures that used to require opening three other
/// screens to piece together.
///
/// The complaint this answers: a student opened the app onto "My thesis" — a
/// record, not an answer — and had to work out for themselves where things
/// stood.
class StudentOverview extends ConsumerWidget {
  const StudentOverview({super.key});

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, $hour:$minute $period';
  }

  /// The soonest defence that has not yet concluded. `myDefencesProvider`
  /// makes no ordering guarantee for every role it serves, so this sorts
  /// locally rather than trusting the list's arrival order.
  static Defence? _nextDefence(List<Defence> defences) {
    final open = defences.where((d) => !d.status.isTerminal).toList()
      ..sort((a, b) {
        final at = a.scheduledAt;
        final bt = b.scheduledAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
    return open.isEmpty ? null : open.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The accent POSITION per tile stays a compile-time constant fixed by
    // where the tile sits; brightness only selects between that position's
    // light and dark variant (spec D14, and every other colour consumer in
    // the app does the same).
    final brightness = Theme.of(context).brightness;
    final thesisAsync = ref.watch(myThesisProvider);
    final needsYouAsync = ref.watch(studentNeedsYouProvider);

    final thesis = thesisAsync.valueOrNull;

    // Its own resolution of the thesis stream, distinct from `.valueOrNull`
    // above: a genuine "no chapters yet" (thesis known, none uploaded) must
    // read as data(empty), not as the loading skeleton that a false zero
    // would otherwise be mistaken for.
    final AsyncValue<List<ThesisChapter>> chaptersAsync = thesisAsync.when(
      data: (t) => t == null
          ? const AsyncValue<List<ThesisChapter>>.data(<ThesisChapter>[])
          : ref.watch(chaptersProvider(t.id)),
      loading: () => const AsyncValue<List<ThesisChapter>>.loading(),
      error: (e, st) => AsyncValue<List<ThesisChapter>>.error(e, st),
    );

    final AsyncValue<String> adviserAsync = thesisAsync.when(
      data: (t) {
        if (t?.adviserUid == null) {
          return const AsyncValue<String>.data('Not yet assigned');
        }
        return ref.watch(allDirectoryProvider).when(
              data: (dir) {
                var found = 'Not yet assigned';
                for (final entry in dir) {
                  if (entry.uid == t!.adviserUid) {
                    found = entry.fullName;
                    break;
                  }
                }
                return AsyncValue<String>.data(found);
              },
              loading: () => const AsyncValue<String>.loading(),
              error: (e, st) => AsyncValue<String>.error(e, st),
            );
      },
      loading: () => const AsyncValue<String>.loading(),
      error: (e, st) => AsyncValue<String>.error(e, st),
    );
    final defencesAsync = ref.watch(myDefencesProvider);

    return PageShell(
      key: const Key('studentOverview'),
      maxWidth: AppTokens.measureWide,
      children: [
        const OverviewGreeting(),
        const Gap.sm(),
        NeedsYouHeadline(
          items: needsYouAsync,
          suffix: thesis?.workingTitle ?? 'your thesis',
        ),
        const Gap.lg(),
        if (thesis != null) ...[
          // The rail reads the real defence and chapter lists rather
          // than a bare "a defence document exists" flag: see ProgressRail's
          // own note on what that flag got wrong.
          ProgressRail(
            status: thesis.status,
            defences: defencesAsync.valueOrNull ?? const [],
            chapters: chaptersAsync.valueOrNull ?? const [],
          ),
          const Gap.lg(),
        ],
        StatTileGrid(children: [
          AsyncStatTile<List<ThesisChapter>>(
            label: 'Chapters approved',
            value: chaptersAsync,
            format: (chapters) => '${chapters.where(
              (c) => c.status == ChapterStatus.approved,
            ).length}',
            unit: '/ 5',
            progress: (chapters) => chapters
                    .where((c) => c.status == ChapterStatus.approved)
                    .length /
                5,
            icon: Icons.task_alt_outlined,
            accent: AppTokens.accentFor(2, brightness),
          ),
          AsyncStatTile<List<ThesisChapter>>(
            label: 'With your adviser',
            value: chaptersAsync,
            format: (chapters) => '${chapters.where(
              (c) => c.status == ChapterStatus.submitted,
            ).length}',
            caption: (chapters) {
              final submitted = chapters
                  .where((c) => c.status == ChapterStatus.submitted)
                  .toList();
              if (submitted.isEmpty) return null;
              return submitted.length == 1
                  ? '1 chapter awaiting review'
                  : '${submitted.length} chapters awaiting review';
            },
            icon: Icons.hourglass_top_outlined,
            accent: AppTokens.accentFor(3, brightness),
          ),
          AsyncStatTile<List<Defence>>(
            label: 'Next defence',
            value: defencesAsync,
            valueIsText: true,
            format: (defences) {
              final next = _nextDefence(defences);
              if (next == null) return 'Not scheduled';
              return next.scheduledAt != null
                  ? _formatDate(next.scheduledAt!)
                  : 'Date to be confirmed';
            },
            caption: (defences) {
              final next = _nextDefence(defences);
              return next == null ? null : '${next.type.label} · ${next.venue}';
            },
            icon: Icons.forum_outlined,
            accent: AppTokens.accentFor(1, brightness),
          ),
          AsyncStatTile<String>(
            label: 'Your adviser',
            value: adviserAsync,
            valueIsText: true,
            format: (name) => name,
            icon: Icons.school_outlined,
            accent: AppTokens.accentFor(0, brightness),
          ),
        ]),
        const Gap.lg(),
        NeedsYouQueue(
          items: needsYouAsync,
          emptyTitle: 'All caught up',
          emptyMessage: 'Nothing needs your attention right now.',
        ),
      ],
    );
  }
}
