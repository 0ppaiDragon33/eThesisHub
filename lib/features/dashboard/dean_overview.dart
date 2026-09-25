import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/metrics.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/agenda.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/stage_donut.dart';
import 'package:ethesishub/features/dashboard/submission_trend.dart';
import 'package:ethesishub/features/notifications/notifications_screen.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Dean's decision docket.
///
/// Organised around the two decisions only the Dean records — approving
/// nominations and closing title defences — with college oversight (the
/// pipeline, the week's defences, the submission trend) beneath them.
///
/// Watches [allThesesProvider] through its charts, which the rules permit
/// only to the dean and coordinator: never reuse this for another role.
class DeanOverview extends ConsumerWidget {
  const DeanOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsYouAsync = ref.watch(deanNeedsYouProvider);
    final approvalsAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.nominationPendingDean));
    final titleDefencesAsync =
        ref.watch(thesesByStatusProvider(ThesisStatus.titlePendingDefence));
    // allDefencesProvider, not myDefencesProvider: the latter branches on a
    // profile that may be missing and would silently fall through to the
    // faculty fan-in.
    final defencesAsync = ref.watch(allDefencesProvider);
    final allThesesAsync = ref.watch(allThesesProvider);

    return KeyedSubtree(
      key: const Key('deanOverview'),
      child: DashboardBody(children: [
        DashboardHeader(
          office: 'Office of the Dean',
          summary: NeedsYouHeadline(items: needsYouAsync, suffix: 'the college'),
          actions: [
            OutlinedButton(
              onPressed: () => context.go('/readiness'),
              child: const Text('Defence readiness'),
            ),
            FilledButton.icon(
              key: const Key('deanOpenReview'),
              onPressed: () => context.push('/review'),
              icon: const Icon(Icons.gavel_outlined, size: 18),
              label: const Text('Open approval queue'),
            ),
          ],
        ),
        MetricStrip(metrics: [
          Metric<List<Thesis>>(
            label: 'Awaiting your approval',
            value: approvalsAsync,
            format: (l) => '${l.length}',
            highlight: (l) => l.isNotEmpty,
            onTap: () => context.go('/approvals'),
          ),
          Metric<List<Thesis>>(
            label: 'At title defence',
            value: titleDefencesAsync,
            format: (l) => '${l.length}',
            caption: (l) => l.isEmpty ? null : 'Only you can close these',
            onTap: () => context.go('/defences?stage=title'),
          ),
          Metric<List<Defence>>(
            label: 'Defences this week',
            value: defencesAsync,
            format: (l) => '${defencesThisWeek(l).length}',
            onTap: () => context.go('/defences'),
          ),
          Metric<List<Thesis>>(
            label: 'Active theses',
            value: allThesesAsync,
            format: (l) => '${activeThesisCount(l)}',
          ),
        ]),
        SplitColumns(
          primary: [
            _DecisionDocket(
              title: 'Nominations to approve',
              subtitle: 'Recommended by the Research Coordinator',
              icon: Icons.gavel_outlined,
              theses: approvalsAsync,
              actionLabel: 'Review',
              routeFor: (_) => '/review',
              emptyText: 'No nominations are waiting on you. They arrive '
                  'here once the Coordinator recommends them.',
            ),
            _DecisionDocket(
              title: 'Title defences to close',
              subtitle: 'Record the approved title or return the set',
              icon: Icons.forum_outlined,
              theses: titleDefencesAsync,
              actionLabel: 'Open defence',
              routeFor: (t) => '/defence/${t.id}',
              emptyText: 'No groups are presenting candidate titles.',
            ),
            NeedsYouQueue(
              items: needsYouAsync,
              title: 'Everything else waiting on you',
              featureFirst: false,
              emptyTitle: 'All caught up',
              emptyMessage: 'Nothing else needs your decision right now.',
            ),
          ],
          secondary: [
            const StageDonut(),
            WeekAgenda(defences: defencesAsync),
            const RecentNotificationsPanel(limit: 3),
          ],
        ),
        const SubmissionTrend(),
      ]),
    );
  }
}

/// A short register of theses awaiting one kind of decision, each with the
/// button that opens it.
class _DecisionDocket extends StatelessWidget {
  const _DecisionDocket({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.theses,
    required this.actionLabel,
    required this.routeFor,
    required this.emptyText,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AsyncValue<List<Thesis>> theses;
  final String actionLabel;
  final String Function(Thesis) routeFor;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final count = theses.valueOrNull?.length ?? 0;

    return Panel(
      title: title,
      subtitle: subtitle,
      icon: icon,
      flush: true,
      emphasis: count > 0,
      trailing: count > 0
          ? ToneBadge(label: '$count waiting', tone: Tone.act, dense: true)
          : null,
      child: theses.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppTokens.md),
          child: LoadingState(),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: ErrorState(error: e, message: 'Could not load this queue.'),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppTokens.lg - 4),
              child: Row(
                children: [
                  Icon(Icons.done_all_rounded,
                      size: 18, color: Tone.endorsed.color(context)),
                  const SizedBox(width: AppTokens.sm),
                  Expanded(child: Text(emptyText, style: text.bodySmall)),
                ],
              ),
            );
          }
          return Column(
            children: [
              for (final t in list)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.lg - 4,
                      vertical: AppTokens.md - 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.rule)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.workingTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: AppTokens.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatusChip(t.status, dense: true),
                                Text(t.program, style: text.bodySmall),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppTokens.md),
                      FilledButton.tonal(
                        key: Key('docket-${t.id}'),
                        onPressed: () => context.push(routeFor(t)),
                        child: Text(actionLabel),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
