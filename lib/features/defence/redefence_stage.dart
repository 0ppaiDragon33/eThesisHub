import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/defence/defence_calendar.dart';
import 'package:ethesishub/features/defence/defence_stage.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Re-defence stage of the Defences page (spec 2026-09-25 §6.3): failed
/// defences still awaiting their re-defence, then the re-defences
/// themselves.
class RedefenceStage extends ConsumerWidget {
  const RedefenceStage({super.key, required this.calendar});

  /// Show the scheduled re-defences as the calendar rather than the list.
  final bool calendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(myDefencesProvider)
        .when(
          loading: () => const LoadingState(label: 'Loading your defences…'),
          error: (e, _) =>
              ErrorState(error: e, message: 'Could not load your defences.'),
          data: (all) {
            final awaiting = awaitingRedefence(all);
            final scheduled = all.any(DefenceStage.redefence.includes);
            if (awaiting.isEmpty && !scheduled) {
              return const EmptyState(
                key: Key('noRedefences'),
                icon: Icons.replay_outlined,
                title: 'No re-defences',
                message:
                    'A group re-defends a stage when the panel\'s '
                    'verdict on it is Fail.',
              );
            }
            final canSchedule =
                ref.watch(currentUserProvider).valueOrNull?.role ==
                UserRole.coordinator;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (awaiting.isNotEmpty)
                  Panel(
                    key: const Key('awaitingRedefence'),
                    title: 'Awaiting a re-defence',
                    subtitle: 'The panel\'s verdict on these was Fail',
                    icon: Icons.replay_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final d in awaiting)
                          AwaitingRedefenceRow(
                            failed: d,
                            canSchedule: canSchedule,
                          ),
                      ],
                    ),
                  ),
                if (awaiting.isNotEmpty && scheduled) const Gap.lg(),
                if (scheduled)
                  calendar
                      ? const DefenceCalendar(where: _isRedefence)
                      : const DefencesList(where: _isRedefence),
              ],
            );
          },
        );
  }
}

bool _isRedefence(Defence d) => d.isRedefence;

/// One failed defence waiting for its re-defence. The Coordinator schedules
/// it from here; everyone else is told it is coming.
class AwaitingRedefenceRow extends ConsumerWidget {
  const AwaitingRedefenceRow({
    super.key,
    required this.failed,
    required this.canSchedule,
  });

  final Defence failed;
  final bool canSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final title = ref
        .watch(thesisByIdProvider(failed.thesisId))
        .valueOrNull
        ?.workingTitle;
    final at = failed.scheduledAt;
    return Padding(
      key: Key('awaitingRedefence-${failed.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title == null || title.isEmpty ? 'Untitled thesis' : title,
            style: text.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            [
              failed.label,
              if (at != null) DefencesList.formatDateTime(at),
              'Verdict: Fail',
            ].join(', '),
            style: text.bodySmall,
          ),
          const Gap.sm(),
          if (canSchedule)
            FilledButton.icon(
              key: Key('scheduleRedefence-${failed.id}'),
              onPressed: () =>
                  context.push('/defence/schedule?redefenceOf=${failed.id}'),
              icon: const Icon(Icons.replay_outlined, size: 18),
              label: const Text('Schedule re-defence'),
            )
          else
            Text(
              'Waiting for the Coordinator to schedule the re-defence.',
              key: Key('awaitingRedefenceNote-${failed.id}'),
              style: text.bodySmall,
            ),
        ],
      ),
    );
  }
}
