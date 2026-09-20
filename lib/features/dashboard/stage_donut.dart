import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/metrics.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The college pipeline: how many theses sit at each [ThesisStage], as one
/// proportional bar with every count written out beneath it.
///
/// Dean and coordinator only — it watches [allThesesProvider], which the
/// rules deny to every other role. Stages are coloured from the accent
/// palette by position: they identify, they do not judge.
///
/// [onStageSelected] lets a host filter its own table to the stage a reader
/// taps, using the same `thesisStage()` buckets so the two always agree.
class StageDonut extends ConsumerWidget {
  const StageDonut({super.key, this.onStageSelected});

  final ValueChanged<ThesisStage>? onStageSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theses = ref.watch(allThesesProvider);
    final total = theses.valueOrNull == null
        ? null
        : activeThesisCount(theses.valueOrNull!);

    return Panel(
      title: 'Theses by stage',
      subtitle: total == null
          ? 'The college pipeline'
          : total == 1
              ? '1 thesis on file'
              : '$total theses on file',
      icon: Icons.stacked_bar_chart_rounded,
      child: theses.when(
        loading: () => const LoadingState(label: 'Loading theses…'),
        error: (error, _) => ErrorState(
          message: 'Could not load the stage breakdown.',
          error: error,
        ),
        data: (all) => _Body(theses: all, onStageSelected: onStageSelected),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.theses, required this.onStageSelected});

  final List<Thesis> theses;
  final ValueChanged<ThesisStage>? onStageSelected;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final stage in ThesisStage.values) stage: 0};
    for (final t in theses) {
      final stage = thesisStage(t.status);
      counts[stage] = (counts[stage] ?? 0) + 1;
    }

    // The same definition the "Active theses" figure uses, so the two
    // numbers on one screen cannot disagree.
    final total = activeThesisCount(theses);
    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
        child: Text(
          'No theses yet. Once groups are underway, their stages appear here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final p = Palette.of(context);
    return SegmentBar(
      key: const Key('stagePipeline'),
      segments: [
        for (var i = 0; i < ThesisStage.values.length; i++)
          (
            label: ThesisStage.values[i].label,
            count: counts[ThesisStage.values[i]]!,
            color: p.accent(i),
          ),
      ],
      onTap: onStageSelected == null
          ? null
          : (i) => onStageSelected!(ThesisStage.values[i]),
    );
  }
}
