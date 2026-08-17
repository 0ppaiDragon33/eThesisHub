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
  // Which of the two nav destinations is showing. 'Groups' still needs a
  // query the rules do not yet permit (a faculty member cannot list theses
  // they advise), so only 'Home' and 'Defences' are declared here — the
  // first time this dashboard has had two, so ResponsiveScaffold shows its
  // navigation for the first time.
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(facultyModeProvider);
    final holdsAdviserPositions = ref.watch(adviserPositionCountProvider) > 0;
    final pendingElsewhere = ref.watch(pendingInOtherModeProvider);
    final pendingAsync = ref.watch(myPendingNominationsProvider);
    final myThesisIdsAsync = ref.watch(myThesisIdsProvider);

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
      // Both sections render regardless of which nav destination is
      // selected — the two destinations exist so ResponsiveScaffold shows
      // navigation at all (it hides itself below two), but there is nothing
      // here yet that needs a full page swap to see. 'Defences' scrolls the
      // rail/bar into the highlighted state; it does not hide the inbox.
      body: PageShell(
        title: mode == FacultyMode.adviser ? 'My advisees' : 'My panels',
        // Says plainly that the list is not built rather than showing an
        // empty area that reads as a failure to load. The mode switch above
        // is real — it remembers your choice — but it has nothing to filter
        // until faculty can list the theses they hold a position on, which
        // needs a security-rules change.
        subtitle: 'Coming with the documents module. For now, the nomination '
            'inbox is where your Conforme requests arrive.',
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
                    message: 'When a group nominates you as their adviser or '
                        'a panel member, the request appears here.',
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
          // One button, always present, regardless of what the count says —
          // two widgets sharing a Key across mutually exclusive branches is
          // the kind of thing that works until a third branch appears.
          FilledButton(
            key: const Key('goToInbox'),
            onPressed: () => context.go('/nominations'),
            child: const Text('Open nomination inbox'),
          ),
          const Gap.lg(),
          Text('Defences', style: Theme.of(context).textTheme.titleMedium),
          const Gap.sm(),
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
