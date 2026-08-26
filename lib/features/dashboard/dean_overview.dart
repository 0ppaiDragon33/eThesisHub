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
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/stage_donut.dart';
import 'package:ethesishub/features/dashboard/submission_trend.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The accent POSITION per tile stays a compile-time constant fixed by
    // where the tile sits; brightness only selects between that position's
    // light and dark variant (spec D14, and every other colour consumer in
    // the app does the same).
    final brightness = Theme.of(context).brightness;
    final needsYouAsync = ref.watch(deanNeedsYouProvider);

    final approvalsAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));
    final titleDefencesAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.titlePendingDefence));
    // allDefencesProvider, not myDefencesProvider: the latter awaits
    // currentUserProvider.future and branches on role, so a dean without a
    // profile document falls through to the faculty adviser/panel fan-in
    // instead of the college-wide watchAll() -- silently wrong, never
    // blocked. See the note on allDefencesProvider itself.
    final defencesAsync = ref.watch(allDefencesProvider);
    final allThesesAsync = ref.watch(allThesesProvider);

    return PageShell(
      key: const Key('deanOverview'),
      maxWidth: AppTokens.measureWide,
      children: [
        const OverviewGreeting(),
        const Gap.sm(),
        NeedsYouHeadline(items: needsYouAsync, suffix: 'the college'),
        const Gap.lg(),
        StatTileGrid(children: [
          AsyncStatTile<List<Thesis>>(
            label: 'Awaiting your approval',
            value: approvalsAsync,
            format: (l) => '${l.length}',
            icon: Icons.gavel_outlined,
            accent: AppTokens.accentFor(3, brightness),
          ),
          AsyncStatTile<List<Thesis>>(
            label: 'Title defences',
            value: titleDefencesAsync,
            format: (l) => '${l.length}',
            icon: Icons.forum_outlined,
            accent: AppTokens.accentFor(1, brightness),
          ),
          AsyncStatTile<List<Defence>>(
            label: 'Defences this week',
            value: defencesAsync,
            format: (l) => '${defencesThisWeek(l).length}',
            icon: Icons.event_note_outlined,
            accent: AppTokens.accentFor(0, brightness),
          ),
          AsyncStatTile<List<Thesis>>(
            label: 'Active theses',
            value: allThesesAsync,
            // The same definition the stage donut below uses. See
            // [activeThesisCount] for which one was chosen and why.
            format: (l) => '${activeThesisCount(l)}',
            icon: Icons.school_outlined,
            accent: AppTokens.accentFor(2, brightness),
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
