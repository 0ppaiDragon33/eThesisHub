import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

class FacultyDashboard extends ConsumerStatefulWidget {
  const FacultyDashboard({super.key});

  @override
  ConsumerState<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends ConsumerState<FacultyDashboard> {
  // Which of the two nav destinations is showing. Only 'Home' and 'Defences'
  // are declared here — the first time this dashboard has had two, so
  // ResponsiveScaffold shows its navigation for the first time.
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(facultyModeProvider);
    final holdsAdviserPositions = ref.watch(adviserPositionCountProvider) > 0;
    final pendingElsewhere = ref.watch(pendingInOtherModeProvider);
    final pendingAsync = ref.watch(myPendingNominationsProvider);
    final myThesisIdsAsync = ref.watch(myThesisIdsProvider);
    final adviseesAsync = ref.watch(myAdviseesProvider);

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('facultyDashboard'),
      title: 'eThesisHub',
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      destinations: const [
        NavDestination(label: 'Home', icon: Icons.home_outlined),
        NavDestination(label: 'Defences', icon: Icons.forum_outlined),
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
      // The two nav destinations now genuinely swap the body — 'Home' (the
      // default) shows the nomination inbox, 'Defences' shows the defences
      // list. Rendering both regardless of selection (the previous shape)
      // read as a broken tab rather than an unbuilt one, exactly the
      // pattern the M1a design pass removed nine destinations to avoid.
      body: _selectedIndex == 0
          ? PageShell(
              title: mode == FacultyMode.adviser ? 'My advisees' : 'My panels',
              // The adviser arm on `allow list` (theses) landed in M2 Task 3,
              // which is what makes a real query possible here at all — see
              // watchAdvisedTheses. Panel listing has no equivalent rule yet,
              // so panelist mode still falls back to the nomination inbox
              // summary below rather than claiming a list it cannot show.
              subtitle: mode == FacultyMode.adviser
                  ? 'Chapters I–V for each thesis you advise.'
                  : 'Panel listings are not built yet. Your Conforme '
                      'requests still arrive in the nomination inbox below.',
              children: [
                if (mode == FacultyMode.adviser) ...[
                  // Its own loading/error handling, kept separate from
                  // pendingAsync below: collapsing this into `data(const [])`
                  // while the query is still in flight would render an empty
                  // state indistinguishable from "no advisees", which this
                  // project has already shipped as a bug four times.
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
                            message: 'Once a group nominates you as adviser '
                                'and the Dean approves, their thesis appears '
                                'here.',
                          )
                        : Column(
                            children: [
                              for (final thesis in advisees)
                                Card(
                                  child: ListTile(
                                    key: Key('advisee-${thesis.id}'),
                                    title: Text(thesis.workingTitle),
                                    subtitle: Text(
                                        '${thesis.college} • ${thesis.program}'),
                                    trailing: FilledButton(
                                      key: Key('openChapters-${thesis.id}'),
                                      onPressed: () => context.go(
                                          '/thesis/chapters?id=${thesis.id}'),
                                      child: const Text('Open'),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const Gap.lg(),
                ],
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
                          message:
                              'When a group nominates you as their adviser or '
                              'a panel member, the request appears here.',
                        )
                      : EmptyState(
                          icon: Icons.mark_email_unread_outlined,
                          title: pending.length == 1
                              ? '1 nomination waiting'
                              : '${pending.length} nominations waiting',
                          message:
                              'Each one needs your Conforme before the group '
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
            )
          : PageShell(
              title: 'Defences',
              subtitle: 'Theses whose candidate titles are ready for you to '
                  'review as a panel member.',
              children: [
                myThesisIdsAsync.when(
                  loading: () => const LoadingState(),
                  error: (e, _) => ErrorState(
                    error: e,
                    message: 'Could not load your defences.',
                  ),
                  data: (thesisIds) => _DefencesList(thesisIds: thesisIds),
                ),
              ],
            ),
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
