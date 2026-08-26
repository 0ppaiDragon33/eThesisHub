import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';
import 'package:ethesishub/core/widgets/stat_tile_grid.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/all_theses_table.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/stage_donut.dart';
import 'package:ethesishub/features/dashboard/submission_trend.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Where the coordinator lands: a greeting, what needs a recommendation or
/// a decision, the four figures that used to require opening several
/// separate screens, the full roster with a filter, and the two
/// college-wide charts.
///
/// [AllThesesTable], [StageDonut] and [SubmissionTrend] all watch
/// [allThesesProvider] directly, which the security rules permit only for
/// the coordinator and the dean -- this overview must never be reused for
/// another role.
class CoordinatorOverview extends ConsumerWidget {
  const CoordinatorOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The accent POSITION per tile stays a compile-time constant fixed by
    // where the tile sits; brightness only selects between that position's
    // light and dark variant (spec D14, and every other colour consumer in
    // the app does the same).
    final brightness = Theme.of(context).brightness;
    final needsYouAsync = ref.watch(coordinatorNeedsYouProvider);

    final allThesesAsync = ref.watch(allThesesProvider);
    final recommendAsync = ref.watch(
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator));
    // allDefencesProvider, not myDefencesProvider: the latter awaits
    // currentUserProvider.future and branches on role, so a coordinator
    // without a profile document falls through to the faculty adviser/panel
    // fan-in instead of the college-wide watchAll() -- silently wrong,
    // never blocked. See the note on allDefencesProvider itself.
    final defencesAsync = ref.watch(allDefencesProvider);
    final directoryAsync = ref.watch(allDirectoryProvider);

    return PageShell(
      key: const Key('coordinatorOverview'),
      maxWidth: AppTokens.measureWide,
      children: [
        const OverviewGreeting(),
        const Gap.sm(),
        NeedsYouHeadline(items: needsYouAsync, suffix: 'the college'),
        const Gap.lg(),
        StatTileGrid(children: [
          AsyncStatTile<List<Thesis>>(
            label: 'Active theses',
            value: allThesesAsync,
            // The same definition the stage donut below uses. See
            // [activeThesisCount] for which one was chosen and why.
            format: (l) => '${activeThesisCount(l)}',
            icon: Icons.school_outlined,
            accent: AppTokens.accentFor(0, brightness),
          ),
          AsyncStatTile<List<Thesis>>(
            label: 'Awaiting your recommendation',
            value: recommendAsync,
            format: (l) => '${l.length}',
            icon: Icons.fact_check_outlined,
            accent: AppTokens.accentFor(3, brightness),
          ),
          AsyncStatTile<List<Defence>>(
            label: 'Defences this week',
            value: defencesAsync,
            format: (l) => '${defencesThisWeek(l).length}',
            icon: Icons.event_note_outlined,
            accent: AppTokens.accentFor(1, brightness),
          ),
          AsyncStatTile<List<FacultyDirectoryEntry>>(
            label: 'Faculty accounts',
            value: directoryAsync,
            format: (l) => '${l.length}',
            icon: Icons.badge_outlined,
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
        const AllThesesTable(),
        const Gap.lg(),
        const StageDonut(),
        const Gap.lg(),
        const SubmissionTrend(),
      ],
    );
  }
}
