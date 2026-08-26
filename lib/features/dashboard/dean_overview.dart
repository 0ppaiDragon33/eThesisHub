import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';
import 'package:ethesishub/core/widgets/stat_tile_grid.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/stage_donut.dart';
import 'package:ethesishub/features/dashboard/submission_trend.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Where the dean lands: a greeting, what needs a decision, the four figures
/// that used to require opening three separate screens, and the two
/// college-wide charts.
///
/// [StageDonut] and [SubmissionTrend] both watch [allThesesProvider]
/// directly, which the security rules permit only for the dean and
/// coordinator -- this overview must never be reused for another role.
class DeanOverview extends ConsumerWidget {
  const DeanOverview({super.key});

  /// Defences scheduled within the next 7 days, today included. Mirrors the
  /// filter `faculty_overview.dart` applies to the same provider, kept
  /// inline here rather than as a private top-level provider since the dean
  /// has only the one tile that needs it.
  static List<Defence> _thisWeek(List<Defence> defences) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 7));
    return defences.where((d) {
      final at = d.scheduledAt;
      if (at == null) return false;
      final day = DateTime(at.year, at.month, at.day);
      return !day.isBefore(today) && day.isBefore(end);
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsYouAsync = ref.watch(deanNeedsYouProvider);

    // Never blocks on the profile document: an earlier milestone locked a
    // signed-in member out by gating a control on `users/{uid}` existing.
    final name = ref.watch(currentUserProvider).valueOrNull?.fullName ?? '';
    final first = name.trim().split(RegExp(r'\s+')).first;
    final greeting = first.isEmpty ? 'Good day' : 'Good day, $first';

    final approvalsAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));
    final titleDefencesAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.titlePendingDefence));
    final defencesAsync = ref.watch(myDefencesProvider);
    final allThesesAsync = ref.watch(allThesesProvider);

    return PageShell(
      key: const Key('deanOverview'),
      maxWidth: AppTokens.measureWide,
      children: [
        Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
        const Gap.sm(),
        NeedsYouHeadline(items: needsYouAsync, suffix: 'the college'),
        const Gap.lg(),
        StatTileGrid(children: [
          AsyncStatTile<List<Thesis>>(
            label: 'Awaiting your approval',
            value: approvalsAsync,
            format: (l) => '${l.length}',
            icon: Icons.gavel_outlined,
            accent: AppTokens.accents[3],
          ),
          AsyncStatTile<List<Thesis>>(
            label: 'Title defences',
            value: titleDefencesAsync,
            format: (l) => '${l.length}',
            icon: Icons.forum_outlined,
            accent: AppTokens.accents[1],
          ),
          AsyncStatTile<List<Defence>>(
            label: 'Defences this week',
            value: defencesAsync,
            format: (l) => '${_thisWeek(l).length}',
            icon: Icons.event_note_outlined,
            accent: AppTokens.accents[0],
          ),
          AsyncStatTile<List<Thesis>>(
            label: 'Active theses',
            value: allThesesAsync,
            format: (l) => '${l.length}',
            icon: Icons.school_outlined,
            accent: AppTokens.accents[2],
          ),
        ]),
        const Gap.lg(),
        NeedsYouQueue(
          items: needsYouAsync,
          emptyTitle: 'All caught up',
          emptyMessage: 'Nothing needs your decision right now.',
        ),
        const Gap.lg(),
        const StageDonut(),
        const Gap.lg(),
        const SubmissionTrend(),
      ],
    );
  }
}
