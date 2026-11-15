import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

// Every row has one fixed height, on both sides of the table. The criterion
// column and the grades are two separate columns of rows, so the only thing
// that keeps a label level with its numbers is that both sides agree on the
// height.
const double _headingHeight = 72;
const double _sectionHeight = 40;
const double _criterionHeight = 56;
const double _totalHeight = 52;
const double _ratingHeight = 48;

/// The narrowest a panelist's column gets: wide enough for a full name on
/// two or three lines.
const double _gradeColumnMin = 120;

/// The grades of a defense, criteria down and panelists across.
///
/// The criterion column stays where it is. Only the panelists' columns slide
/// sideways, so on a phone a row never loses its label. On a wide screen the
/// panelists' columns share the space and nothing slides.
class GradesTable extends StatefulWidget {
  const GradesTable({
    super.key,
    required this.evaluations,
    required this.evaluatorLabel,
  });

  final List<Evaluation> evaluations;
  final String Function(Evaluation) evaluatorLabel;

  @override
  State<GradesTable> createState() => _GradesTableState();
}

class _GradesTableState extends State<GradesTable> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final p = Palette.of(context);
    final evaluations = widget.evaluations;

    // Theme colours, not literals: this screen has to survive the dark
    // toggle. The tint keeps a section header from reading as one more
    // criterion, and the final-grade row from reading as one more line.
    final sectionTint =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final totalTint =
        theme.colorScheme.primaryContainer.withValues(alpha: 0.35);
    final primary = theme.colorScheme.primary;

    Widget row(
      double height,
      Widget child, {
      Key? key,
      Color? color,
      AlignmentGeometry alignment = Alignment.centerLeft,
    }) =>
        Container(
          key: key,
          height: height,
          alignment: alignment,
          decoration: BoxDecoration(
            color: color,
            border: Border(bottom: BorderSide(color: p.rule)),
          ),
          child: child,
        );

    const labelPadding = EdgeInsets.symmetric(horizontal: AppTokens.md);

    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(AppTokens.radius + 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final labelWidth = constraints.maxWidth < 600 ? 150.0 : 230.0;
        final n = evaluations.length;
        final available = constraints.maxWidth - labelWidth - 1;
        final columnWidth =
            n == 0 ? _gradeColumnMin : math.max(_gradeColumnMin, available / n);

        Widget scores(
          double height,
          Widget Function(Evaluation e) cell, {
          Key? key,
          Color? color,
        }) =>
            row(
              height,
              Row(children: [
                for (final e in evaluations)
                  SizedBox(
                    width: columnWidth,
                    child: Center(child: cell(e)),
                  ),
              ]),
              key: key,
              color: color,
            );

        final left = <Widget>[
          row(
            _headingHeight,
            Padding(
              padding: labelPadding,
              child: Text('Criterion',
                  style: text.labelMedium?.copyWith(color: p.muted)),
            ),
          ),
        ];
        final right = <Widget>[
          scores(
            _headingHeight,
            (e) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm),
              child: Text(
                widget.evaluatorLabel(e),
                key: ValueKey('heading_${e.evaluatorUid}'),
                // Wrap, so a full name is readable.
                softWrap: true,
                maxLines: 3,
                textAlign: TextAlign.center,
                style: text.labelMedium?.copyWith(color: p.muted),
              ),
            ),
          ),
        ];

        for (final section in EvaluationSection.values) {
          left.add(row(
            _sectionHeight,
            Padding(
              padding: labelPadding,
              child: Text(
                '${section.label}, out of ${EvaluationSection.sectionTotal}',
                style: text.labelMedium,
              ),
            ),
            key: ValueKey('section_${section.name}'),
            color: sectionTint,
          ));
          right.add(scores(
            _sectionHeight,
            (_) => const SizedBox.shrink(),
            key: ValueKey('scores_section_${section.name}'),
            color: sectionTint,
          ));

          for (final c in evaluationCriteria.where((c) => c.section == section)) {
            left.add(row(
              _criterionHeight,
              Padding(
                padding: labelPadding,
                // The weight travels with the criterion, so a 6 beside /10
                // and a 6 beside /25 are not read as the same performance.
                child: Text(
                  '${c.label}  /${c.weight}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ),
              key: ValueKey('criterion_${c.key}'),
            ));
            right.add(scores(
              _criterionHeight,
              (e) => Text(
                '${e.scores[c.key] ?? 0}',
                key: ValueKey('score_${c.key}_${e.evaluatorUid}'),
                style: text.bodyMedium,
              ),
              key: ValueKey('scores_criterion_${c.key}'),
            ));
          }
        }

        // The row the whole sheet exists to produce.
        left.add(row(
          _totalHeight,
          Padding(
            padding: labelPadding,
            child: Text('Final grade',
                style: text.titleSmall?.copyWith(color: primary)),
          ),
          key: const ValueKey('row_total'),
          color: totalTint,
        ));
        right.add(scores(
          _totalHeight,
          (e) => Text(
            '${e.total}',
            key: ValueKey('total_${e.evaluatorUid}'),
            style: text.titleSmall?.copyWith(color: primary),
          ),
          key: const ValueKey('scores_total'),
          color: totalTint,
        ));

        left.add(row(
          _ratingHeight,
          Padding(padding: labelPadding, child: const Text('Rating')),
          key: const ValueKey('row_rating'),
        ));
        right.add(scores(
          _ratingHeight,
          (e) => Text(
            e.rating?.label ?? '—',
            key: ValueKey('rating_${e.evaluatorUid}'),
          ),
          key: const ValueKey('scores_rating'),
        ));

        return Row(
          key: const Key('gradesTable'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: p.rule)),
              ),
              child: SizedBox(
                width: labelWidth,
                child: Column(children: left),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  key: const Key('gradesScroll'),
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: columnWidth * n,
                    child: Column(children: right),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
