import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

const _monthLabels = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Submissions per month over the trailing seven months, for the dean and
/// coordinator dashboards — it watches [allThesesProvider] directly, which
/// the security rules deny to every other role.
///
/// The header always states its own range ("Past 7 months") so a young
/// college with only a couple of points reads as young data rather than as
/// a broken chart.
class SubmissionTrend extends ConsumerWidget {
  const SubmissionTrend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theses = ref.watch(allThesesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Submissions',
                  style: TextStyle(
                    fontFamily: AppTheme.serif,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: AppTokens.sm),
                Text(
                  'Past 7 months',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.md),
            theses.when(
              loading: () => const LoadingState(label: 'Loading submissions…'),
              error: (error, _) => ErrorState(
                message: 'Could not load the submission trend.',
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

class _MonthBucket {
  _MonthBucket(this.year, this.month);
  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      other is _MonthBucket && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// `createdAt` is non-nullable on [Thesis] today — the repository backfills
/// a missing server timestamp with "now" before this model ever sees it —
/// but this panel is written against the honest contract (a submission date
/// can be absent) rather than today's fallback, so a future change that
/// surfaces a genuine null does not silently misdate a thesis into "this
/// month" instead of excluding it.
DateTime? _submissionDate(Thesis t) => t.createdAt;

class _Body extends StatelessWidget {
  const _Body({required this.theses});

  final List<Thesis> theses;

  /// The trailing seven months, oldest first, ending on the current month.
  List<_MonthBucket> _trailingMonths() {
    final now = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        () {
          // Walk back i months from the current one, borrowing a year when
          // the month index runs negative.
          var y = now.year;
          var m = now.month - i;
          while (m <= 0) {
            m += 12;
            y -= 1;
          }
          return _MonthBucket(y, m);
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final months = _trailingMonths();
    final counts = {for (final m in months) m: 0};

    var excluded = 0;
    for (final t in theses) {
      final createdAt = _submissionDate(t);
      if (createdAt == null) {
        excluded++;
        continue;
      }
      final bucket = _MonthBucket(createdAt.year, createdAt.month);
      if (counts.containsKey(bucket)) {
        counts[bucket] = counts[bucket]! + 1;
      }
    }

    final maxCount = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    final lineColor = AppTokens.accentFor(1, Theme.of(context).brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (excluded > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.sm),
            child: Text(
              excluded == 1
                  ? '1 thesis without a submission date is excluded.'
                  : '$excluded theses without a submission date are excluded.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              // At least 1 so a flat all-zero trailing window still draws a
              // visible axis instead of collapsing to a single line.
              maxY: maxCount == 0 ? 1 : maxCount.toDouble() * 1.2,
              lineTouchData: const LineTouchData(enabled: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxCount == 0 ? 1 : null,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppTokens.rule,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= months.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _monthLabels[months[i].month - 1],
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < months.length; i++)
                      FlSpot(i.toDouble(), counts[months[i]]!.toDouble()),
                  ],
                  isCurved: true,
                  color: lineColor,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: lineColor.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
