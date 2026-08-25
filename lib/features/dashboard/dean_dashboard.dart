import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/defence_queue.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class DeanDashboard extends ConsumerStatefulWidget {
  const DeanDashboard({super.key});

  @override
  ConsumerState<DeanDashboard> createState() => _DeanDashboardState();
}

class _DeanDashboardState extends ConsumerState<DeanDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final queueAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('deanDashboard'),
      title: 'eThesisHub',
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      // Only approvals resolve today; 'Overview' was a label for the screen
      // you are already on, and defences and reports belong to unbuilt
      // modules.
      // Three sections that were stacked on one scrolling page, each now
      // its own destination. They answer different questions on different
      // days -- who needs a decision, who is defending, who is ready to be
      // scheduled -- and stacking them made the newest the least visible.
      destinations: const [
        NavDestination(label: 'Approvals', icon: Icons.gavel_outlined),
        // Two different jobs, so two destinations. Approving a candidate
        // title set is not attending a scheduled defence, and stacking
        // them put an empty title queue above the rooms that had content.
        NavDestination(label: 'Titles', icon: Icons.forum_outlined),
        NavDestination(label: 'Defences', icon: Icons.event_note_outlined),
        NavDestination(label: 'Readiness', icon: Icons.checklist_outlined),
      ],
      actions: const [SignOutButton()],
      body: switch (_selectedIndex) {
        1 => const PageShell(
            title: 'Title defences',
            subtitle: 'Groups presenting their candidate titles.',
            children: [DefenceQueue()],
          ),
        2 => const PageShell(
            title: 'Scheduled defences',
            subtitle: 'Pre-oral and final defences, and the rooms they run '
                'in.',
            children: [DefencesList()],
          ),
        3 => const PageShell(
            title: 'Defence readiness',
            subtitle: 'Theses whose chapters have cleared the gate for a '
                'pre-oral or final defence.',
            children: [DefenceReadinessList()],
          ),
        _ => PageShell(
        title: 'Nomination approvals',
        subtitle: 'Theses the Coordinator has recommended, waiting on you.',
        children: [
          queueAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState(
              error: e,
              message: 'Could not load the approval queue.',
            ),
            data: (theses) {
              if (theses.isEmpty) {
                return const EmptyState(
                  icon: Icons.task_alt,
                  title: 'Nothing waiting',
                  message: 'Nominations appear here once the College '
                      'Research Coordinator has recommended them.',
                );
              }
              return Column(
                children: [
                  for (final t in theses)
                    ListTile(
                      title: Text(t.workingTitle),
                      subtitle: Text('${t.program} · ${t.college}'),
                      trailing: StatusChip(t.status, dense: true),
                    ),
                ],
              );
            },
          ),
          const Gap.lg(),
          FilledButton(
            key: const Key('goToReview'),
            onPressed: () => context.go('/review'),
            child: const Text('Open approval queue'),
          ),
        ],
          ),
      },
    );
  }
}
