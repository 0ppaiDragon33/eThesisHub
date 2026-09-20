import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/metrics.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/agenda.dart';
import 'package:ethesishub/features/dashboard/all_theses_table.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/stage_donut.dart';
import 'package:ethesishub/features/dashboard/submission_trend.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The research office console.
///
/// A command row for the office's recurring jobs, the office's figures,
/// the work queue beside the pipeline and the week's defences, and the
/// full college register — which the pipeline bar filters when tapped.
///
/// Reads [allThesesProvider], permitted only to the coordinator and dean:
/// never reuse this for another role.
class CoordinatorOverview extends ConsumerStatefulWidget {
  const CoordinatorOverview({super.key});

  @override
  ConsumerState<CoordinatorOverview> createState() =>
      _CoordinatorOverviewState();
}

class _CoordinatorOverviewState extends ConsumerState<CoordinatorOverview> {
  final _stageFilter = ValueNotifier<ThesisStage?>(null);

  @override
  void dispose() {
    _stageFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsYouAsync = ref.watch(coordinatorNeedsYouProvider);
    final allThesesAsync = ref.watch(allThesesProvider);
    final recommendAsync = ref.watch(
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator));
    final stalledAsync = ref.watch(stalledThesesProvider);
    final defencesAsync = ref.watch(allDefencesProvider);
    final directoryAsync = ref.watch(allDirectoryProvider);

    return KeyedSubtree(
      key: const Key('coordinatorOverview'),
      child: DashboardBody(children: [
        DashboardHeader(
          office: 'Research office',
          summary:
              NeedsYouHeadline(items: needsYouAsync, suffix: 'the college'),
          actions: [
            FilledButton.icon(
              key: const Key('coordOpenReview'),
              onPressed: () => context.push('/review'),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Open review queue'),
            ),
          ],
        ),
        const _CommandRow(),
        MetricStrip(metrics: [
          Metric<List<Thesis>>(
            label: 'Active theses',
            value: allThesesAsync,
            format: (l) => '${activeThesisCount(l)}',
          ),
          Metric<List<Thesis>>(
            label: 'Awaiting your recommendation',
            value: recommendAsync,
            format: (l) => '${l.length}',
            highlight: (l) => l.isNotEmpty,
            onTap: () => context.go('/recommendations'),
          ),
          Metric<List<Defence>>(
            label: 'Defences this week',
            value: defencesAsync,
            format: (l) => '${defencesThisWeek(l).length}',
            onTap: () => context.go('/defences'),
          ),
          Metric<List<FacultyDirectoryEntry>>(
            label: 'Faculty accounts',
            value: directoryAsync,
            format: (l) => '${l.length}',
            onTap: () => context.go('/users'),
          ),
        ]),
        SplitColumns(
          primary: [
            NeedsYouQueue(
              items: needsYouAsync,
              emptyTitle: 'All caught up',
              emptyMessage: 'Nothing needs your decision right now.',
            ),
            _StalledNotice(stalled: stalledAsync),
          ],
          secondary: [
            StageDonut(
              onStageSelected: (stage) => _stageFilter.value = stage,
            ),
            WeekAgenda(defences: defencesAsync),
          ],
        ),
        AllThesesTable(filter: _stageFilter),
        const SubmissionTrend(),
      ]),
    );
  }
}

/// The office's recurring jobs, one tap each. Every target is a route the
/// coordinator's guards admit.
class _CommandRow extends StatelessWidget {
  const _CommandRow();

  @override
  Widget build(BuildContext context) {
    final commands = <({IconData icon, String label, String detail, VoidCallback go})>[
      (
        icon: Icons.event_available_outlined,
        label: 'Schedule a defence',
        detail: 'Choose a ready thesis',
        go: () => context.go('/readiness'),
      ),
      (
        icon: Icons.person_add_alt_outlined,
        label: 'Invite faculty',
        detail: 'Send an account invite',
        go: () => context.go('/invites'),
      ),
      (
        icon: Icons.calendar_month_outlined,
        label: 'Defence calendar',
        detail: 'Every scheduled session',
        go: () => context.go('/defences'),
      ),
      (
        icon: Icons.local_library_outlined,
        label: 'Publish to archive',
        detail: 'Finished manuscripts',
        go: () => context.push('/archive/queue'),
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final across = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 480 ? 2 : 1);
      final w = (c.maxWidth - (across - 1) * AppTokens.md) / across;
      return Wrap(
        spacing: AppTokens.md,
        runSpacing: AppTokens.md,
        children: [
          for (final cmd in commands)
            SizedBox(
              width: w,
              child: _CommandTile(
                icon: cmd.icon,
                label: cmd.label,
                detail: cmd.detail,
                onTap: cmd.go,
              ),
            ),
        ],
      );
    });
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: p.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: BorderSide(color: p.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: p.seal.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: p.seal),
              ),
              const SizedBox(width: AppTokens.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nominations stalled by a declined nominee, which only this office can
/// reopen. Hidden when there are none.
class _StalledNotice extends StatelessWidget {
  const _StalledNotice({required this.stalled});

  final AsyncValue<List<Thesis>> stalled;

  @override
  Widget build(BuildContext context) {
    final list = stalled.valueOrNull;
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final c = Tone.returned.color(context);
    return Panel(
      child: Row(
        children: [
          Icon(Icons.report_outlined, color: c),
          const SizedBox(width: AppTokens.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.length == 1
                      ? '1 nomination is stalled'
                      : '${list.length} nominations are stalled',
                  style: text.labelLarge?.copyWith(color: c),
                ),
                Text('A nominee declined. Reopen the thesis for '
                    're-nomination.', style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.sm),
          TextButton(
            key: const Key('coordOpenStalled'),
            onPressed: () => context.push('/stalled'),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }
}
