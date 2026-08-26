import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/features/dashboard/advisees_screen.dart';
import 'package:ethesishub/features/dashboard/faculty_overview.dart';
import 'package:ethesishub/features/dashboard/panels_screen.dart';
import 'package:ethesishub/features/defence/defences_screen.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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
        2 => const DefencesScreen(
            title: 'My defences',
            subtitle: 'Pre-oral and final defences you are attending, '
                'whether you advise the group or sit on its panel.',
          ),
        3 => _nominationsBody(pendingAsync),
        _ => mode == FacultyMode.adviser
            ? const AdviseesScreen()
            : const PanelsScreen(),
      },
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
