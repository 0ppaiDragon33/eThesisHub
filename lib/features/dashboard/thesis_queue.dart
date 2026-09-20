import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis.dart';

/// A register of theses waiting on one decision, shared by the Dean's and
/// Coordinator's queue destinations.
///
/// Each row names the group, its program and how long it has waited, and
/// carries the one button that opens the decision.
class ThesisQueue extends StatelessWidget {
  const ThesisQueue({
    super.key,
    required this.theses,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.rowAction,
    this.waitingSince,
    this.errorMessage = 'Could not load this queue.',
  });

  final AsyncValue<List<Thesis>> theses;
  final String emptyTitle;
  final String emptyMessage;
  final String errorMessage;

  /// The button for a row.
  final Widget Function(BuildContext context, Thesis thesis) rowAction;

  /// The date the thesis entered this queue, when the record carries one.
  final DateTime? Function(Thesis thesis)? waitingSince;

  @override
  Widget build(BuildContext context) {
    return theses.when(
      loading: () => const LoadingState(label: 'Loading the queue…'),
      error: (e, _) => ErrorState(error: e, message: errorMessage),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt_rounded,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        final sorted = [...list]..sort((a, b) {
            final at = waitingSince?.call(a) ?? a.createdAt;
            final bt = waitingSince?.call(b) ?? b.createdAt;
            return at.compareTo(bt);
          });
        return FadeIn(child: Panel(
          title: list.length == 1 ? '1 waiting' : '${list.length} waiting',
          subtitle: 'Longest waiting first',
          icon: Icons.pending_actions_outlined,
          flush: true,
          child: Column(
            children: [
              for (final t in sorted)
                _QueueRow(
                  thesis: t,
                  since: waitingSince?.call(t),
                  action: rowAction(context, t),
                ),
            ],
          ),
        ));
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.thesis,
    required this.since,
    required this.action,
  });

  final Thesis thesis;
  final DateTime? since;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final meta = [
      if (thesis.program.isNotEmpty) thesis.program,
      if (thesis.college.isNotEmpty) thesis.college,
      if (since != null) 'waiting since ${Dates.dayShort(since!)}',
    ].join(', ');

    return Container(
      key: Key('queueRow-${thesis.id}'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg - 4, vertical: AppTokens.md - 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final words = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(thesis.workingTitle, style: text.titleMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(thesis.status, dense: true),
                if (thesis.memberNames.isNotEmpty)
                  Text('${thesis.memberNames.length} members',
                      style: text.bodySmall),
              ],
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(meta, style: text.bodySmall),
            ],
          ],
        );
        if (c.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [words, const SizedBox(height: AppTokens.sm), action],
          );
        }
        return Row(
          children: [
            Expanded(child: words),
            const SizedBox(width: AppTokens.md),
            action,
          ],
        );
      }),
    );
  }
}
