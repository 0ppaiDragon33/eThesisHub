import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
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
      subtitle: 'Candidate titles ready for your review, and the other '
          'theses you sit on.',
      children: [
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

/// Resolves each thesis id and splits it into "to review" and "others".
/// Its own widget: it watches a dynamic number of family instances.
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
        message: 'When you are nominated onto a thesis panel and accept, '
            'it appears here.',
      );
    }

    final advised = ref
            .watch(myAdviseesProvider)
            .valueOrNull
            ?.map((t) => t.id)
            .toSet() ??
        const <String>{};

    final review = <Thesis>[];
    final others = <Thesis>[];
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
        others.add(t);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (review.isEmpty)
          EmptyState(
            icon: Icons.forum_outlined,
            title: 'No title sets waiting',
            message: pending > 0
                ? 'Still loading $pending of your theses…'
                : 'None of your theses are at title defence right now.',
          )
        else
          Panel(
            title: 'Title sets to review',
            subtitle: 'Read the candidates and leave your comments',
            icon: Icons.fact_check_outlined,
            emphasis: true,
            flush: true,
            trailing: ToneBadge(
              label: '${review.length} waiting',
              tone: Tone.act,
              dense: true,
            ),
            child: Column(
              children: [
                for (final t in review)
                  _PanelRow(
                    thesis: t,
                    action: FilledButton(
                      key: Key('goToDefence-${t.id}'),
                      onPressed: () => context.push('/defence/${t.id}'),
                      child: const Text('Open title defence'),
                    ),
                  ),
              ],
            ),
          ),
        if (!reviewOnly && others.isNotEmpty) ...[
          const Gap.lg(),
          Panel(
            title: 'Your other panels',
            subtitle: 'For reference; nothing waits on you here',
            icon: Icons.groups_outlined,
            flush: true,
            child: Column(
              children: [
                for (final t in others)
                  _PanelRow(
                    thesis: t,
                    action: t.status == ThesisStatus.titleApproved
                        ? TextButton(
                            onPressed: () =>
                                context.go('/defences?stage=preOral'),
                            child: const Text('View defences'),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.thesis, required this.action});

  final Thesis thesis;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg - 4, vertical: AppTokens.md - 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppTokens.md,
        runSpacing: AppTokens.sm,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(thesis.workingTitle, style: text.titleMedium),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(thesis.status, dense: true),
                    const SizedBox(width: AppTokens.sm),
                    Flexible(
                      child: Text(
                        thesis.program,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}
