import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class DeanDashboard extends ConsumerWidget {
  const DeanDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('deanDashboard'),
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      // Only approvals resolve today; 'Overview' was a label for the screen
      // you are already on, and defences and reports belong to unbuilt
      // modules.
      destinations: const [],
      actions: const [SignOutButton()],
      body: PageShell(
        title: 'Nomination approvals',
        subtitle: 'Theses the Coordinator has recommended, waiting on you.',
        children: [
          queueAsync.when(
            loading: () => const LoadingState(),
            error: (_, _) => const ErrorState(
              message: 'Could not load the approval queue. Check your '
                  'connection and try again.',
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
    );
  }
}
