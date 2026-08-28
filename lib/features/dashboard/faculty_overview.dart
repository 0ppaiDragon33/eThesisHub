import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';
import 'package:ethesishub/core/widgets/stat_tile_grid.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// Chapters `submitted` across every thesis the signed-in member advises --
/// the adviser-mode "chapters awaiting your review" tile. A tile-only figure,
/// unlike [facultyNeedsYouProvider]: per spec D17 the queue itself must never
/// be filtered by mode, but a TILE summarising "the work of this mode" is
/// exactly what D5 asks for.
final _chaptersAwaitingReviewProvider = FutureProvider<int>((ref) async {
  final advisees = await ref.watch(myAdviseesProvider.future);
  var count = 0;
  for (final thesis in advisees) {
    final chapters = await ref.watch(chaptersProvider(thesis.id).future);
    count +=
        chapters.where((c) => c.status == ChapterStatus.submitted).length;
  }
  return count;
});

/// Candidate title sets ready for panel review: theses the signed-in member
/// sits on as a panelist (not adviser) that are at
/// [ThesisStatus.titlePendingDefence]. The panelist-mode "title sets to
/// review" tile.
final _titleSetsToReviewProvider = FutureProvider<int>((ref) async {
  final ids = await ref.watch(myThesisIdsProvider.future);
  final advisees = await ref.watch(myAdviseesProvider.future);
  final advised = advisees.map((t) => t.id).toSet();
  var count = 0;
  for (final id in ids.where((id) => !advised.contains(id))) {
    final thesis = await ref.watch(thesisByIdProvider(id).future);
    if (thesis?.status == ThesisStatus.titlePendingDefence) count++;
  }
  return count;
});

/// Defences scheduled within the next 7 days, today included. Shared by both
/// modes -- a defence is on the calendar whichever position brought you to
/// it, and `myDefencesProvider` already covers both.
///
/// The window itself is [defencesThisWeek], the one definition the dean and
/// coordinator tiles use too. It stays a provider here only because the
/// SOURCE differs by role: this reads `myDefencesProvider`, and the two
/// college-wide roles read `allDefencesProvider`, which the rules permit
/// only to them.
final _defencesThisWeekProvider = FutureProvider<int>((ref) async {
  final defences = await ref.watch(myDefencesProvider.future);
  return defencesThisWeek(defences).length;
});

/// Where a faculty member lands: a greeting, what needs them regardless of
/// mode (spec D17), and the four figures for whichever position -- adviser
/// or panelist -- the mode switch currently has them looking at (spec D5).
///
/// The queue below the tiles and the tiles themselves read from genuinely
/// different sources on purpose: [facultyNeedsYouProvider] never reads the
/// mode, the tiles always do.
class FacultyOverview extends ConsumerWidget {
  const FacultyOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The accent POSITION per tile stays a compile-time constant fixed by
    // where the tile sits; brightness only selects between that position's
    // light and dark variant (spec D14, and every other colour consumer in
    // the app does the same).
    final brightness = Theme.of(context).brightness;
    final modeAsync = ref.watch(effectiveFacultyModeProvider);
    final needsYouAsync = ref.watch(facultyNeedsYouProvider);

    // This used to call `requireValue`, on the strength of
    // `FacultyDashboard` resolving the mode before it ever built this
    // widget. That dashboard is gone — `/overview` renders this directly
    // now — so the unresolved case is reachable and has to be answered
    // here.
    //
    // It is answered per-SECTION, not per-page: the greeting, the
    // headline and the queue below are all mode-independent (spec D17)
    // and have their own loading states already, so only the tile grid
    // waits. Replacing the whole overview with a spinner or an error is
    // what spec §9 forbids — a dashboard that replaces itself strands the
    // reader with no way to reach the screens that do work.
    //
    // And the mode is not defaulted while it resolves. That was the
    // hard-won rule in faculty_dashboard.dart: guessing shows a panelist
    // the adviser's four tiles and then swaps them out from under them on
    // every launch.
    //
    // `modeAsync.isLoading` (no snapshot yet) is a genuinely different
    // question from `mode == null` (a resolved answer of "neither
    // capability"): `effectiveFacultyModeProvider` can now settle on `null`
    // as real data, and treating that the same as "still resolving" would
    // spin the tile section's loading state forever for a member on leave
    // rather than simply omitting it (spec §6).
    final stillResolving = modeAsync.isLoading;
    final mode = modeAsync.valueOrNull;

    final adviseesAsync = ref.watch(myAdviseesProvider);
    final nominationsAsync = ref.watch(myPendingNominationsProvider);
    final chaptersAwaitingAsync = ref.watch(_chaptersAwaitingReviewProvider);
    final defencesThisWeekAsync = ref.watch(_defencesThisWeekProvider);
    final panelCountAsync = ref.watch(panelPositionCountProvider);
    final titleSetsAsync = ref.watch(_titleSetsToReviewProvider);

    return PageShell(
      key: const Key('facultyOverview'),
      maxWidth: AppTokens.measureWide,
      children: [
        const OverviewGreeting(),
        const Gap.sm(),
        NeedsYouHeadline(
          items: needsYouAsync,
          suffix: 'your advisees and panels',
        ),
        const Gap.lg(),
        if (stillResolving)
          const LoadingState(label: 'Working out which positions you hold…')
        else if (mode == null)
          // Neither designated nor holding a position for either mode --
          // resolved, not loading. There is no tile set to show and none is
          // owed; the greeting, headline and queue above and below already
          // cover everything mode-independent (spec D17).
          const SizedBox.shrink()
        else
          StatTileGrid(
            children: mode == FacultyMode.adviser
                ? [
                    AsyncStatTile<int>(
                      label: 'Chapters awaiting your review',
                      value: chaptersAwaitingAsync,
                      format: (n) => '$n',
                      icon: Icons.hourglass_top_outlined,
                      accent: AppTokens.accentFor(3, brightness),
                    ),
                    AsyncStatTile<List<Thesis>>(
                      label: 'Advisees',
                      value: adviseesAsync,
                      format: (l) => '${l.length}',
                      icon: Icons.school_outlined,
                      accent: AppTokens.accentFor(0, brightness),
                    ),
                    AsyncStatTile<int>(
                      label: 'Defences this week',
                      value: defencesThisWeekAsync,
                      format: (n) => '$n',
                      icon: Icons.event_note_outlined,
                      accent: AppTokens.accentFor(1, brightness),
                    ),
                    AsyncStatTile<
                        List<({String thesisId, Nomination nomination})>>(
                      label: 'Conforme requests',
                      value: nominationsAsync,
                      format: (l) => '${l.length}',
                      icon: Icons.drafts_outlined,
                      accent: AppTokens.accentFor(2, brightness),
                    ),
                  ]
                : [
                    AsyncStatTile<int>(
                      label: 'Panels',
                      value: panelCountAsync,
                      format: (n) => '$n',
                      icon: Icons.forum_outlined,
                      accent: AppTokens.accentFor(0, brightness),
                    ),
                    AsyncStatTile<int>(
                      label: 'Title sets to review',
                      value: titleSetsAsync,
                      format: (n) => '$n',
                      icon: Icons.fact_check_outlined,
                      accent: AppTokens.accentFor(3, brightness),
                    ),
                    AsyncStatTile<int>(
                      label: 'Defences this week',
                      value: defencesThisWeekAsync,
                      format: (n) => '$n',
                      icon: Icons.event_note_outlined,
                      accent: AppTokens.accentFor(1, brightness),
                    ),
                    AsyncStatTile<
                        List<({String thesisId, Nomination nomination})>>(
                      label: 'Conforme requests',
                      value: nominationsAsync,
                      format: (l) => '${l.length}',
                      icon: Icons.drafts_outlined,
                      accent: AppTokens.accentFor(2, brightness),
                    ),
                  ],
          ),
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
