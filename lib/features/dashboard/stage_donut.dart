import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// How many theses sit at each [ThesisStage], for the dean and coordinator
/// dashboards only — it watches [allThesesProvider] directly, which the
/// security rules deny to every other role.
///
/// The donut is decoration. The legend beside it is where the numbers live,
/// and it is laid out so it keeps its own share of the width via [Expanded]
/// rather than depending on the donut succeeding first — a chart that fails
/// to lay out in a cramped space must never take the counts down with it.
class StageDonut extends ConsumerWidget {
  const StageDonut({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theses = ref.watch(allThesesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theses by stage',
              style: TextStyle(
                fontFamily: AppTheme.serif,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppTokens.md),
            theses.when(
              loading: () => const LoadingState(label: 'Loading theses…'),
              error: (error, _) => ErrorState(
                message: 'Could not load the stage breakdown.',
                error: error,
              ),
              data: (all) => _Body(theses: all),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.theses});

  final List<Thesis> theses;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final stage in ThesisStage.values) stage: 0};
    for (final t in theses) {
      final stage = thesisStage(t.status);
      counts[stage] = (counts[stage] ?? 0) + 1;
    }

    // The same definition the "Active theses" tile above uses, so the two
    // numbers on this screen cannot disagree. See [activeThesisCount].
    final total = activeThesisCount(theses);
    if (total == 0) {
      return const EmptyState(
        title: 'No theses yet',
        message: 'Once theses are underway, their stages will appear here.',
        icon: Icons.donut_large_outlined,
      );
    }

    final brightness = Theme.of(context).brightness;

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sections: [
                  for (var i = 0; i < ThesisStage.values.length; i++)
                    if (counts[ThesisStage.values[i]]! > 0)
                      PieChartSectionData(
                        value: counts[ThesisStage.values[i]]!.toDouble(),
                        color: AppTokens.accentFor(i, brightness),
                        radius: 28,
                        showTitle: false,
                      ),
                ],
                centerSpaceRadius: 36,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(enabled: false),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            flex: 3,
            child: _Legend(counts: counts, brightness: brightness),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.counts, required this.brightness});

  final Map<ThesisStage, int> counts;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < ThesisStage.values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTokens.accentFor(i, brightness),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Text(
                    ThesisStage.values[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ),
                Text(
                  '${counts[ThesisStage.values[i]]}',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
