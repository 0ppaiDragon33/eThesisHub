import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class FacultyDashboard extends ConsumerWidget {
  const FacultyDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(facultyModeProvider);
    final holdsAdviserPositions = ref.watch(adviserPositionCountProvider) > 0;
    final pendingElsewhere = ref.watch(pendingInOtherModeProvider);
    final pendingAsync = ref.watch(myPendingNominationsProvider);

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('facultyDashboard'),
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      // 'Groups' needs a query the rules do not yet permit (a faculty member
      // cannot list theses they advise), and 'Defenses' belongs to an
      // unbuilt module. Neither is declared until it works.
      destinations: const [],
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
        ],
      ),
    );
  }
}
