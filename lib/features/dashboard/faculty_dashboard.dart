import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/faculty_overview.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

class FacultyDashboard extends ConsumerStatefulWidget {
  const FacultyDashboard({super.key});

  @override
  ConsumerState<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends ConsumerState<FacultyDashboard> {
  // Which destination is showing. Both modes declare two — the work of the
  // mode you are in, then Nominations — so the index never has to be clamped
  // when the mode changes under it.
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final modeAsync = ref.watch(effectiveFacultyModeProvider);
    final holdsAdviserPositions =
        (ref.watch(adviserPositionCountProvider).valueOrNull ?? 0) > 0;
    final pendingElsewhere =
        ref.watch(pendingInOtherModeProvider).valueOrNull ?? 0;
    final pendingAsync = ref.watch(myPendingNominationsProvider);
    final myThesisIdsAsync = ref.watch(myThesisIdsProvider);
    final adviseesAsync = ref.watch(myAdviseesProvider);

    // The mode decides which destinations exist, so nothing can be drawn
    // until it resolves. Defaulting while it loads would show a panelist the
    // Advisees tab and then swap it out from under them on every launch.
    if (modeAsync.isLoading) {
      return const Scaffold(
        body: LoadingState(label: 'Loading your dashboard…'),
      );
    }
    if (modeAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('eThesisHub')),
        body: PageShell(children: [
          ErrorState(
            error: modeAsync.error,
            message: 'Could not work out which positions you hold.',
          ),
        ]),
      );
    }
    final mode = modeAsync.requireValue;

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('facultyDashboard'),
      title: 'eThesisHub',
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      // Destinations sit INSIDE the mode, per design decision D5: the switch
      // is the primary axis and each mode is its own clean dashboard. Overview
      // is first and mode-independent -- its queue deliberately ignores the
      // switch (D17) even though its tiles do not. The destination after it
      // is whatever the mode is for; Nominations appears in both, because a
      // Conforme request is role-neutral — it is how you acquire either
      // position in the first place.
      destinations: [
        const NavDestination(
            label: 'Overview', icon: Icons.dashboard_outlined),
        mode == FacultyMode.adviser
            ? const NavDestination(
                label: 'Advisees', icon: Icons.school_outlined)
            : const NavDestination(
                label: 'Panels', icon: Icons.forum_outlined),
        // Its own destination in BOTH modes rather than a section under
        // each. Stacked under Panels it sat below the title-defence queue,
        // so an empty queue was the first thing a panelist saw and their
        // actual schedule was underneath it.
        const NavDestination(
            label: 'Defences', icon: Icons.event_note_outlined),
        const NavDestination(
            label: 'Nominations', icon: Icons.drafts_outlined),
      ],
      actions: [
        if (holdsAdviserPositions)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              isLabelVisible: pendingElsewhere > 0,
              label: Text('$pendingElsewhere'),
              child: SegmentedButton<FacultyMode>(
                segments: const [
                  ButtonSegment(
                    value: FacultyMode.adviser,
                    label: Text('Adviser'),
                  ),
                  ButtonSegment(
                    value: FacultyMode.panelist,
                    label: Text('Panelist'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => ref
                    .read(facultyModeProvider.notifier)
                    .set(selection.first),
              ),
            ),
          ),
        const SignOutButton(),
      ],
      // Destination 0 is Overview, mode-independent; destination 1 is the
      // work of the mode you are in; destination 3 is the Conforme inbox,
      // which belongs to neither. Rendering more than one body at once read
      // as a broken tab rather than an unbuilt one, in the previous shape.
      body: switch (_selectedIndex) {
        0 => const FacultyOverview(),
        2 => const PageShell(
            title: 'My defences',
            subtitle: 'Pre-oral and final defences you are attending, '
                'whether you advise the group or sit on its panel.',
            children: [DefencesList()],
          ),
        3 => _nominationsBody(pendingAsync),
        _ => _modeBody(mode, adviseesAsync, myThesisIdsAsync),
      },
    );
  }

  /// Whatever the current mode is for: the theses you advise, or the panels
  /// you sit on.
  Widget _modeBody(
    FacultyMode mode,
    AsyncValue<List<Thesis>> adviseesAsync,
    AsyncValue<List<String>> myThesisIdsAsync,
  ) {
    if (mode == FacultyMode.adviser) {
      return PageShell(
        title: 'My advisees',
        subtitle: 'Chapters I–V for each thesis you advise.',
        children: [
          // Its own loading and error handling. Collapsing this into
          // `data(const [])` while the query is in flight renders an empty
          // state indistinguishable from "no advisees" — a bug this project
          // has shipped four times.
          adviseesAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(
              error: e,
              message: 'Could not load your advisees.',
            ),
            data: (advisees) => advisees.isEmpty
                ? const EmptyState(
                    icon: Icons.school_outlined,
                    title: 'No advisees yet',
                    message: 'Once a group nominates you as adviser and the '
                        'Dean approves, their thesis appears here.',
                  )
                : Column(
                    children: [
                      for (final thesis in advisees)
                        _AdviseeCard(thesis: thesis),
                    ],
                  ),
          ),

        ],
      );
    }

    return PageShell(
      title: 'My panels',
      subtitle: 'Theses whose candidate titles are ready for you to review '
          'as a panel member.',
      children: [
        myThesisIdsAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(
            error: e,
            message: 'Could not load your panels.',
          ),
          data: (thesisIds) => _DefencesList(thesisIds: thesisIds),
        ),
      ],
    );
  }

  /// The Conforme inbox, which belongs to neither mode — a nomination is how
  /// you acquire a position in the first place.
  Widget _nominationsBody(
    AsyncValue<List<({String thesisId, Nomination nomination})>> pendingAsync,
  ) {
    return PageShell(
      title: 'Nominations',
      subtitle: 'Requests waiting on your Conforme.',
      children: [
        pendingAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(
            error: e,
            message: 'Could not load your nominations.',
          ),
          data: (pending) => pending.isEmpty
              ? const EmptyState(
                  icon: Icons.drafts_outlined,
                  title: 'No nominations waiting',
                  message: 'When a group nominates you as their adviser or a '
                      'panel member, the request appears here.',
                )
              : EmptyState(
                  icon: Icons.mark_email_unread_outlined,
                  title: pending.length == 1
                      ? '1 nomination waiting'
                      : '${pending.length} nominations waiting',
                  message: 'Each one needs your Conforme before the group '
                      'can move forward.',
                ),
        ),
        const Gap.lg(),
        FilledButton(
          key: const Key('goToInbox'),
          onPressed: () => context.go('/nominations'),
          child: const Text('Open nomination inbox'),
        ),
      ],
    );
  }
}

/// Resolves each thesis id the signed-in faculty member holds a position on
/// and lists the ones currently at [ThesisStatus.titlePendingDefence].
///
/// A separate widget because it watches one [thesisByIdProvider] per id —
/// a dynamic number of family instances that the parent's single build
/// cannot loop over with `ref.watch` outside of a build method of its own.
class _DefencesList extends ConsumerWidget {
  const _DefencesList({required this.thesisIds});

  final List<String> thesisIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (thesisIds.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No defences yet',
        message: 'When you are nominated on a thesis whose candidate titles '
            'reach the panel, it appears here.',
      );
    }

    final rows = <Widget>[];
    for (final id in thesisIds) {
      final thesis = ref.watch(thesisByIdProvider(id)).valueOrNull;
      if (thesis == null || thesis.status != ThesisStatus.titlePendingDefence) {
        continue;
      }
      rows.add(
        Card(
          child: ListTile(
            title: Text(thesis.workingTitle),
            subtitle: const Text(
                'Candidate titles are ready for the panel to review.'),
            trailing: FilledButton(
              key: Key('goToDefence-$id'),
              onPressed: () => context.go('/defence/$id'),
              child: const Text('Open'),
            ),
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No defences waiting',
        message: 'None of your theses are currently at title defence.',
      );
    }

    return Column(children: rows);
  }
}

/// One advisee's row, with a count of chapters `submitted` -- uploaded by
/// the student, not yet responded to by the adviser.
///
/// Spec §7 requires this count ("advised theses with a count of chapters
/// awaiting review") so an adviser with several advisees can tell which
/// groups have work waiting without opening every one and clicking through
/// every chapter. A separate widget, same shape as `_DefencesList` above:
/// a dynamic number of `chaptersProvider` family instances cannot be
/// looped over with `ref.watch` inside the parent's single build.
class _AdviseeCard extends ConsumerWidget {
  const _AdviseeCard({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider(thesis.id));

    return Card(
      child: ListTile(
        key: Key('advisee-${thesis.id}'),
        title: Text(thesis.workingTitle),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${thesis.college} • ${thesis.program}'),
            // While the stream is still loading, this must NOT read "0
            // awaiting" -- that is indistinguishable from nothing actually
            // waiting, the single most repeated bug in this codebase (see
            // `_ReadinessRow` in defence_readiness.dart and `_DefencesList`
            // above, which apply the same rule).
            chaptersAsync.when(
              loading: () => const Text('Awaiting review: still loading…'),
              error: (e, _) =>
                  const Text('Could not load this thesis\'s chapters.'),
              data: (chapters) {
                final awaiting = chapters
                    .where((c) => c.status == ChapterStatus.submitted)
                    .length;
                return Text(awaiting == 0
                    ? 'Nothing awaiting review'
                    : awaiting == 1
                        ? '1 chapter awaiting review'
                        : '$awaiting chapters awaiting review');
              },
            ),
          ],
        ),
        trailing: FilledButton(
          key: Key('openChapters-${thesis.id}'),
          onPressed: () => context.go('/thesis/chapters?id=${thesis.id}'),
          child: const Text('Open'),
        ),
      ),
    );
  }
}
