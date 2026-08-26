import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Dean's Approvals destination: theses the Coordinator has
/// recommended, waiting on the Dean's decision.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));

    return PageShell(
      key: const Key('approvalsScreen'),
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
    );
  }
}
