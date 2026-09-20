import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/metrics.dart';
import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/advisees_screen.dart';
import 'package:ethesishub/features/dashboard/agenda.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/panels_screen.dart';
import 'package:ethesishub/features/notifications/notifications_screen.dart';
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

/// The faculty desk.
///
/// The inbox is mode-independent (spec D17) and leads the page. The figure
/// strip and the roster below follow the mode switch in the top bar
/// (spec D5): an adviser sees their advisees and chapters waiting, a
/// panelist sees the title sets waiting. The week's defences sit beside
/// them whichever position brought the member to each.
class FacultyOverview extends ConsumerWidget {
  const FacultyOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeAsync = ref.watch(effectiveFacultyModeProvider);
    final needsYouAsync = ref.watch(facultyNeedsYouProvider);

    // `isLoading` (no answer yet) and `mode == null` (a resolved answer of
    // "neither position") are different: the second simply omits the
    // mode-specific sections rather than spinning forever. The mode is
    // never guessed while it resolves.
    final stillResolving = modeAsync.isLoading;
    final mode = modeAsync.valueOrNull;

    final adviseesAsync = ref.watch(myAdviseesProvider);
    final nominationsAsync = ref.watch(myPendingNominationsProvider);
    final chaptersAwaitingAsync = ref.watch(_chaptersAwaitingReviewProvider);
    final defencesThisWeekAsync = ref.watch(_defencesThisWeekProvider);
    final panelCountAsync = ref.watch(panelPositionCountProvider);
    final titleSetsAsync = ref.watch(_titleSetsToReviewProvider);
    final myDefencesAsync = ref.watch(myDefencesProvider);
    final idsAsync = ref.watch(myThesisIdsProvider);

    final office = switch (mode) {
      FacultyMode.adviser => 'Faculty, adviser view',
      FacultyMode.panelist => 'Faculty, panelist view',
      null => 'Faculty',
    };

    final conforme = Metric<List<({String thesisId, Nomination nomination})>>(
      label: 'Conforme requests',
      value: nominationsAsync,
      format: (l) => '${l.length}',
      highlight: (l) => l.isNotEmpty,
      caption: (l) => l.isEmpty ? 'None to answer' : 'Accept or decline',
      onTap: () => context.go('/nominations'),
    );
    final week = Metric<int>(
      label: 'Defences this week',
      value: defencesThisWeekAsync,
      format: (n) => '$n',
      onTap: () => context.go('/defences'),
    );

    final Widget modeSection;
    if (stillResolving) {
      modeSection =
          const LoadingState(label: 'Working out which positions you hold…');
    } else if (mode == null) {
      modeSection = const SizedBox.shrink();
    } else if (mode == FacultyMode.adviser) {
      modeSection = MetricStrip(metrics: [
        Metric<int>(
          label: 'Chapters awaiting your review',
          value: chaptersAwaitingAsync,
          format: (n) => '$n',
          highlight: (n) => n > 0,
          onTap: () => context.go('/advisees'),
        ),
        Metric<List<Thesis>>(
          label: 'Advisees',
          value: adviseesAsync,
          format: (l) => '${l.length}',
          onTap: () => context.go('/advisees'),
        ),
        week,
        conforme,
      ]);
    } else {
      modeSection = MetricStrip(metrics: [
        Metric<int>(
          label: 'Title sets to review',
          value: titleSetsAsync,
          format: (n) => '$n',
          highlight: (n) => n > 0,
          onTap: () => context.go('/panels'),
        ),
        Metric<int>(
          label: 'Panels',
          value: panelCountAsync,
          format: (n) => '$n',
          onTap: () => context.go('/panels'),
        ),
        week,
        conforme,
      ]);
    }

    final Widget roster = switch (mode) {
      FacultyMode.adviser when !stillResolving =>
        const AdviseeRegister(limit: 5, title: 'Your advisees'),
      FacultyMode.panelist when !stillResolving => idsAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) =>
              ErrorState(error: e, message: 'Could not load your panels.'),
          data: (ids) => PanelRegister(thesisIds: ids, reviewOnly: true),
        ),
      _ => const SizedBox.shrink(),
    };

    return KeyedSubtree(
      key: const Key('facultyOverview'),
      child: DashboardBody(children: [
        DashboardHeader(
          office: office,
          animateKey: mode,
          summary: NeedsYouHeadline(
            items: needsYouAsync,
            suffix: 'your advisees and panels',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go('/nominations'),
              icon: const Icon(Icons.drafts_outlined, size: 18),
              label: const Text('Nomination inbox'),
            ),
            if (mode != null)
              ModeSwap<FacultyMode>(
                value: mode,
                forward: mode == FacultyMode.panelist,
                child: FilledButton.icon(
                  onPressed: () => context.go(
                      mode == FacultyMode.adviser ? '/advisees' : '/panels'),
                  icon: Icon(
                    mode == FacultyMode.adviser
                        ? Icons.school_outlined
                        : Icons.forum_outlined,
                    size: 18,
                  ),
                  label: Text(mode == FacultyMode.adviser
                      ? 'My advisees'
                      : 'My panels'),
                ),
              ),
          ],
        ),
        ModeSwap<FacultyMode?>(
          value: stillResolving ? null : mode,
          forward: mode != FacultyMode.adviser,
          child: modeSection,
        ),
        SplitColumns(
          primary: [
            NeedsYouQueue(
              items: needsYouAsync,
              emptyTitle: 'All caught up',
              emptyMessage: 'Nothing needs your attention right now.',
            ),
            ModeSwap<FacultyMode?>(
              value: stillResolving ? null : mode,
              forward: mode != FacultyMode.adviser,
              child: roster,
            ),
          ],
          secondary: [
            WeekAgenda(defences: myDefencesAsync),
            const RecentNotificationsPanel(),
          ],
        ),
      ]),
    );
  }
}
