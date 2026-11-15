import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/metrics.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/switch_mode_notice.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// The panelist's desk: title sets waiting for your judgement first, then
/// every other thesis you sit on, with where each stands.
class PanelsScreen extends ConsumerWidget {
  const PanelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idsAsync = ref.watch(myThesisIdsProvider);

    return PageShell(
      key: const Key('panelsScreen'),
      maxWidth: AppTokens.measureWide,
      kicker: 'Panelist',
      title: 'My panels',
      subtitle: 'Titles to review and theses you sit on.',
      children: [
        const SwitchModeNotice(
          needed: FacultyMode.panelist,
          message: 'Switch to Panelist mode to use your panels.',
        ),
        idsAsync.when(
          loading: () => const LoadingState(label: 'Loading your panels…'),
          error: (e, _) =>
              ErrorState(error: e, message: 'Could not load your panels.'),
          data: (ids) => PanelRegister(thesisIds: ids),
        ),
      ],
    );
  }
}

/// Resolves each thesis id and splits it into "to review", "active" and
/// "archived". Its own widget: it watches a dynamic number of family
/// instances.
class PanelRegister extends ConsumerWidget {
  const PanelRegister({
    super.key,
    required this.thesisIds,
    this.reviewOnly = false,
  });

  final List<String> thesisIds;

  /// The overview shows only the actionable section.
  final bool reviewOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (thesisIds.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No panels yet',
        message: 'Panels you join appear here.',
      );
    }

    final advised = ref
            .watch(myAdviseesProvider)
            .valueOrNull
            ?.map((t) => t.id)
            .toSet() ??
        const <String>{};

    // Opening a title defense to comment on it is panel work: disabled in
    // Adviser mode. The switch notice at the top of the screen offers the
    // way back.
    final canAct = ref.watch(modeAllowsProvider(FacultyMode.panelist));

    final review = <Thesis>[];
    final active = <Thesis>[];
    final archived = <Thesis>[];
    var pending = 0;
    for (final id in thesisIds) {
      final async = ref.watch(thesisByIdProvider(id));
      final t = async.valueOrNull;
      if (t == null) {
        if (async.isLoading) pending++;
        continue;
      }
      if (t.status == ThesisStatus.titlePendingDefence) {
        review.add(t);
      } else if (!advised.contains(t.id)) {
        (t.status == ThesisStatus.archived ? archived : active).add(t);
      }
    }
    int newestFirst(Thesis a, Thesis b) => b.createdAt.compareTo(a.createdAt);
    active.sort(newestFirst);
    archived.sort(newestFirst);

    // Never a false zero while theses are still loading.
    AsyncValue<int> count(int n) =>
        pending > 0 ? const AsyncLoading<int>() : AsyncData<int>(n);

    VoidCallback? go(String path) =>
        canAct ? () => context.push(path) : null;

    Widget tileFor(Thesis t) {
      if (t.status == ThesisStatus.titlePendingDefence) {
        return _PanelTile(
          key: Key('panelTile-${t.id}'),
          thesis: t,
          onTap: go('/defence/${t.id}'),
          action: FilledButton(
            key: Key('goToDefence-${t.id}'),
            onPressed: go('/defence/${t.id}'),
            child: const Text('Open title defense'),
          ),
        );
      }
      if (t.status == ThesisStatus.archived) {
        return _PanelTile(
          key: Key('panelTile-${t.id}'),
          thesis: t,
          onTap: () => context.push('/archive/${t.id}'),
          action: OutlinedButton(
            key: Key('viewArchivedPanel-${t.id}'),
            onPressed: () => context.push('/archive/${t.id}'),
            child: const Text('View in the archive'),
          ),
        );
      }
      if (t.status == ThesisStatus.titleApproved) {
        return _PanelTile(
          key: Key('panelTile-${t.id}'),
          thesis: t,
          onTap: () => context.go('/defences?stage=preOral'),
          action: TextButton(
            onPressed: () => context.go('/defences?stage=preOral'),
            child: const Text('View defenses'),
          ),
        );
      }
      return _PanelTile(key: Key('panelTile-${t.id}'), thesis: t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!reviewOnly) ...[
          MetricStrip(metrics: [
            Metric<int>(
              label: 'Title sets to review',
              value: count(review.length),
              format: (n) => '$n',
              highlight: (n) => n > 0,
              caption: (n) =>
                  n == 0 ? 'Nothing to review' : 'Read and leave comments',
            ),
            Metric<int>(
              label: 'Active panels',
              value: count(active.length),
              format: (n) => '$n',
              caption: (_) => 'Theses in progress',
            ),
            Metric<int>(
              label: 'Archived',
              value: count(archived.length),
              format: (n) => '$n',
              caption: (_) => 'Completed theses',
            ),
          ]),
          const Gap.lg(),
        ],
        if (review.isEmpty)
          _AllCaughtUp(
            loading: pending > 0,
            message: pending > 0
                ? 'Still loading $pending of your theses…'
                : 'None of your theses are at title defense right now.',
          )
        else
          Panel(
            title: 'Title sets to review',
            subtitle: 'Read the candidates and leave your comments',
            icon: Icons.fact_check_outlined,
            emphasis: true,
            trailing: ToneBadge(
              label: '${review.length} waiting',
              tone: Tone.act,
              dense: true,
            ),
            child: _TileGrid(tiles: [for (final t in review) tileFor(t)]),
          ),
        if (!reviewOnly && active.isNotEmpty) ...[
          const Gap.lg(),
          Panel(
            title: 'Active panels',
            subtitle: 'For reference; nothing waits on you here',
            icon: Icons.groups_outlined,
            trailing: ToneBadge(
              label: '${active.length}',
              tone: Tone.neutral,
              dense: true,
            ),
            child: _TileGrid(tiles: [for (final t in active) tileFor(t)]),
          ),
        ],
        if (!reviewOnly && archived.isNotEmpty) ...[
          const Gap.lg(),
          Panel(
            title: 'Archived panels',
            subtitle: 'Finished theses you sat on',
            icon: Icons.inventory_2_outlined,
            trailing: ToneBadge(
              label: '${archived.length}',
              tone: Tone.neutral,
              dense: true,
            ),
            child: _TileGrid(tiles: [for (final t in archived) tileFor(t)]),
          ),
        ],
      ],
    );
  }
}

/// Lays tiles out three across on a wide screen, two on a medium one and one
/// on a phone, so a short list fills the width instead of floating in it.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
      const gap = AppTokens.md;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }
}

/// One thesis you sit on: where it stands, who the group is, and what you
/// can do with it.
class _PanelTile extends StatelessWidget {
  const _PanelTile({
    super.key,
    required this.thesis,
    this.action,
    this.onTap,
  });

  final Thesis thesis;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    final changed = thesis.approvedTitleText;
    final title =
        (changed != null && changed.isNotEmpty) ? changed : thesis.workingTitle;
    final meta = [thesis.program, thesis.academicYear]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    final leader = thesis.leaderName;
    final members = thesis.memberNames.length;
    final group = [
      if (leader != null && leader.isNotEmpty) 'Led by $leader',
      if (members > 0) members == 1 ? '1 member' : '$members members',
    ].join(' · ');

    final radius = BorderRadius.circular(AppTokens.radius + 2);
    return Material(
      color: p.paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: p.rule),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  StatusChip(thesis.status, dense: true),
                  const Spacer(),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: p.muted),
                ],
              ),
              const SizedBox(height: AppTokens.sm),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: AppTokens.xs),
                Text(meta, style: text.bodySmall),
              ],
              if (group.isNotEmpty) ...[
                const SizedBox(height: AppTokens.xs),
                Text(group, style: text.bodySmall),
              ],
              if (action != null) ...[
                const SizedBox(height: AppTokens.md),
                Align(alignment: Alignment.centerLeft, child: action!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The "nothing waiting" state, as one slim line rather than a tall empty
/// box, so a quiet day does not take up half the screen.
class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp({required this.message, this.loading = false});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(AppTokens.radius + 2),
        border: Border.all(color: p.rule),
      ),
      child: Row(
        children: [
          Icon(
            loading ? Icons.hourglass_empty_rounded : Icons.check_circle_outline,
            color: loading ? p.muted : Tone.endorsed.color(context),
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No title sets waiting', style: text.titleMedium),
                const SizedBox(height: 2),
                Text(message, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}