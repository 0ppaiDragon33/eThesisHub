import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

/// The panel's written remarks as the group reads them: one card per
/// panelist, and a tap opens that panelist's remarks criterion by
/// criterion. No score appears anywhere in here: [EvaluationRemarks]
/// does not carry one.
class RemarksGrid extends StatelessWidget {
  const RemarksGrid({super.key, required this.remarks});

  final List<EvaluationRemarks> remarks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
        final spacing = AppTokens.sm + 4;
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final (i, r) in remarks.indexed)
              SizedBox(
                width: w,
                child: FadeIn(
                  key: ValueKey('remarksFade-${r.evaluatorUid}'),
                  delay: Duration(milliseconds: 30 * (i < 8 ? i : 8)),
                  child: RemarksCard(remarks: r),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The criteria this grader wrote on, in the form's own order.
List<String> _commentedKeys(EvaluationRemarks r) => [
  for (final k in contentKeys)
    if ((r.comments[k] ?? '').trim().isNotEmpty) k,
];

String _nameOf(EvaluationRemarks r) =>
    r.evaluatorName.isNotEmpty ? r.evaluatorName : 'A panelist';

class RemarksCard extends StatelessWidget {
  const RemarksCard({super.key, required this.remarks});

  final EvaluationRemarks remarks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = Palette.of(context);
    final keys = _commentedKeys(remarks);
    final hasRemarks = keys.isNotEmpty;
    final accent = hasRemarks ? p.seal : muted;

    const maxTags = 3;
    final shown = keys.take(maxTags).toList();
    final extra = keys.length - shown.length;

    return Material(
      key: Key('remarksCard-${remarks.evaluatorUid}'),
      color: p.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: BorderSide(color: p.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // A panelist who wrote nothing has nothing to open.
        onTap: hasRemarks ? () => showRemarksSheet(context, remarks) : null,
        child: Padding(
          padding: EdgeInsets.all(AppTokens.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rate_review_outlined, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    hasRemarks
                        ? '${keys.length} '
                              '${keys.length == 1 ? 'remark' : 'remarks'}'
                        : 'No written remarks',
                    style: text.labelMedium?.copyWith(color: accent),
                  ),
                  const Spacer(),
                  if (hasRemarks)
                    Icon(Icons.chevron_right_rounded, color: muted),
                ],
              ),
              SizedBox(height: AppTokens.sm),
              Text(
                _nameOf(remarks),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge,
              ),
              if (hasRemarks) ...[
                SizedBox(height: AppTokens.xs),
                Text(
                  remarks.comments[keys.first]!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: muted),
                ),
                SizedBox(height: AppTokens.sm + 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in shown) _Pill(criterionFor(k)?.label ?? k),
                    if (extra > 0) _Pill('+$extra more'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.rule),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Opens one panelist's remarks: the name, then each criterion they wrote
/// on with their words set apart under it.
Future<void> showRemarksSheet(BuildContext context, EvaluationRemarks r) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => _RemarksSheet(remarks: r),
  );
}

class _RemarksSheet extends StatelessWidget {
  const _RemarksSheet({required this.remarks});

  final EvaluationRemarks remarks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = Palette.of(context);
    final keys = _commentedKeys(remarks);

    return SingleChildScrollView(
      key: const Key('remarksDetail'),
      padding: EdgeInsets.fromLTRB(
        AppTokens.lg,
        0,
        AppTokens.lg,
        AppTokens.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_nameOf(remarks), style: text.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '${keys.length} ${keys.length == 1 ? 'remark' : 'remarks'} '
            'on your thesis',
            style: text.bodyMedium?.copyWith(color: muted),
          ),
          SizedBox(height: AppTokens.lg),
          for (final (i, k) in keys.indexed) ...[
            if (i > 0) SizedBox(height: AppTokens.md + 2),
            Text(
              criterionFor(k)?.label ?? k,
              style: text.labelLarge?.copyWith(color: p.seal),
            ),
            const SizedBox(height: 6),
            // The words themselves, set off by a rule on the left so they
            // read as the panelist's rather than the app's.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: p.seal, width: 3)),
              ),
              child: SelectableText(
                remarks.comments[k]!,
                style: text.bodyLarge?.copyWith(height: 1.45),
              ),
            ),
          ],
          SizedBox(height: AppTokens.lg),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('closeRemarks'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}
