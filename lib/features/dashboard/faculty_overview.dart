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
import 'package:ethesishub/providers/auth_providers.dart';
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
final _defencesThisWeekProvider = FutureProvider<int>((ref) async {
  final defences = await ref.watch(myDefencesProvider.future);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 7));
  return defences.where((d) {
    final at = d.scheduledAt;
    if (at == null) return false;
    final day = DateTime(at.year, at.month, at.day);
    return !day.isBefore(today) && day.isBefore(end);
  }).length;
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
    final modeAsync = ref.watch(effectiveFacultyModeProvider);
    final needsYouAsync = ref.watch(facultyNeedsYouProvider);

    // Never blocks on the profile document: gating a greeting on
    // `users/{uid}` existing would blank the whole overview for a signed-in
    // member whose profile write is still in flight.
    final name = ref.watch(currentUserProvider).valueOrNull?.fullName ?? '';
    final first = name.trim().split(RegExp(r'\s+')).first;
    final greeting = first.isEmpty ? 'Good day' : 'Good day, $first';

    // The mode decides which four tiles show, so nothing below can be drawn
    // until it resolves -- same reasoning as the dashboard's own gate.
    if (modeAsync.isLoading) {
      return const LoadingState(label: 'Loading your overview…');
    }
    if (modeAsync.hasError) {
      return ErrorState(
        error: modeAsync.error,
        message: 'Could not work out which positions you hold.',
      );
    }
    final mode = modeAsync.requireValue;

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
        Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
        const Gap.sm(),
        NeedsYouHeadline(items: needsYouAsync, suffix: 'your dashboard'),
        const Gap.lg(),
        StatTileGrid(
          children: mode == FacultyMode.adviser
              ? [
                  AsyncStatTile<int>(
                    label: 'Chapters awaiting your review',
                    value: chaptersAwaitingAsync,
                    format: (n) => '$n',
                    icon: Icons.hourglass_top_outlined,
                    accent: AppTokens.accents[3],
                  ),
                  AsyncStatTile<List<Thesis>>(
                    label: 'Advisees',
                    value: adviseesAsync,
                    format: (l) => '${l.length}',
                    icon: Icons.school_outlined,
                    accent: AppTokens.accents[0],
                  ),
                  AsyncStatTile<int>(
                    label: 'Defences this week',
                    value: defencesThisWeekAsync,
                    format: (n) => '$n',
                    icon: Icons.event_note_outlined,
                    accent: AppTokens.accents[1],
                  ),
                  AsyncStatTile<
                      List<({String thesisId, Nomination nomination})>>(
                    label: 'Conforme requests',
                    value: nominationsAsync,
                    format: (l) => '${l.length}',
                    icon: Icons.drafts_outlined,
                    accent: AppTokens.accents[2],
                  ),
                ]
              : [
                  AsyncStatTile<int>(
                    label: 'Panels',
                    value: panelCountAsync,
                    format: (n) => '$n',
                    icon: Icons.forum_outlined,
                    accent: AppTokens.accents[0],
                  ),
                  AsyncStatTile<int>(
                    label: 'Title sets to review',
                    value: titleSetsAsync,
                    format: (n) => '$n',
                    icon: Icons.fact_check_outlined,
                    accent: AppTokens.accents[3],
                  ),
                  AsyncStatTile<int>(
                    label: 'Defences this week',
                    value: defencesThisWeekAsync,
                    format: (n) => '$n',
                    icon: Icons.event_note_outlined,
                    accent: AppTokens.accents[1],
                  ),
                  AsyncStatTile<
                      List<({String thesisId, Nomination nomination})>>(
                    label: 'Conforme requests',
                    value: nominationsAsync,
                    format: (l) => '${l.length}',
                    icon: Icons.drafts_outlined,
                    accent: AppTokens.accents[2],
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
