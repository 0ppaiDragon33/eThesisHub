import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/defence/defence_status.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The next seven days of defences as a dated agenda.
///
/// Uses [defencesThisWeek], the one definition every "this week" figure
/// shares, so the agenda and the count above it always agree.
class WeekAgenda extends StatelessWidget {
  const WeekAgenda({
    super.key,
    required this.defences,
    this.title = 'This week',
  });

  final AsyncValue<List<Defence>> defences;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: title,
      subtitle: 'Defences in the next seven days',
      icon: Icons.event_note_outlined,
      flush: true,
      trailing: TextButton(
        onPressed: () => context.go('/defences?stage=preOral&view=calendar'),
        child: const Text('Calendar'),
      ),
      child: defences.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppTokens.md),
          child: LoadingState(),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: ErrorState(error: e, message: 'Could not load defences.'),
        ),
        data: (all) {
          final week = defencesThisWeek(all)
            ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
          if (week.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppTokens.lg - 4),
              child: Text(
                'No defences scheduled this week.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          return Column(
            children: [for (final d in week) _AgendaRow(defence: d)],
          );
        },
      ),
    );
  }
}

class _AgendaRow extends ConsumerWidget {
  const _AgendaRow({required this.defence});

  final Defence defence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final at = defence.scheduledAt!;
    final title =
        ref.watch(thesisByIdProvider(defence.thesisId)).valueOrNull?.workingTitle;
    final statusColor =
        defenceStatusColor(defence.status, Theme.of(context).brightness);

    return InkWell(
      onTap: () => context.push('/defence/room/${defence.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.lg - 4, vertical: AppTokens.md - 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.rule)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Dates.weekday(at),
                      style: text.labelSmall?.copyWith(color: p.seal)),
                  Text(Dates.time(at), style: text.labelMedium),
                ],
              ),
            ),
            Container(
              width: 2,
              height: 38,
              margin: const EdgeInsets.only(right: AppTokens.md - 4),
              color: statusColor,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? defence.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      if (title != null) defence.label,
                      if (defence.venue.isNotEmpty) defence.venue,
                      defenceStatusLabel(defence.status),
                    ].join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
