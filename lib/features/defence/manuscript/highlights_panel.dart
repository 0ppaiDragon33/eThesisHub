import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/features/defence/manuscript/defence_typing.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Every highlight in page order, with a legend of who is which colour.
class HighlightsList extends StatelessWidget {
  const HighlightsList({
    super.key,
    required this.annotations,
    this.parts,
    required this.colours,
    required this.numbers,
    this.myUid,
    this.canDelete = false,
    this.onSelect,
    this.onDelete,
  });

  /// Oldest first.
  final List<DefenceAnnotation> annotations;

  /// The manuscript as shown now, to mark highlights on an earlier version.
  /// Null while it is still loading: nothing is marked until it is known.
  final List<ManuscriptPart>? parts;
  final Map<String, Color> colours;
  final Map<String, int> numbers;
  final String? myUid;
  final bool canDelete;
  final void Function(DefenceAnnotation)? onSelect;
  final void Function(DefenceAnnotation)? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (annotations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
        child: Text(
          'No highlights yet. Boxes drawn on the manuscript appear here.',
          key: const Key('highlightsEmpty'),
          style: text.bodySmall,
        ),
      );
    }
    final legend = highlightLegend(annotations, colours);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: const Key('highlightLegend'),
          spacing: AppTokens.md,
          runSpacing: AppTokens.xs,
          children: [
            for (final a in legend)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: a.colour, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(a.name, style: text.labelMedium),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppTokens.sm),
        for (final a in inPageOrder(annotations)) _row(context, a),
      ],
    );
  }

  Widget _row(BuildContext context, DefenceAnnotation a) {
    final text = Theme.of(context).textTheme;
    final numeral = chapterNumeral(a.chapter);
    final current = parts == null || isOnCurrentVersion(a, parts!);
    final colour = colours[a.authorUid] ?? kHighlightPalette.last;
    return InkWell(
      key: Key('highlightRow-${a.id}'),
      onTap: current && onSelect != null ? () => onSelect!(a) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HighlightTag(number: numbers[a.id] ?? 0, colour: colour),
            const SizedBox(width: AppTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.authorName}, ${a.authorPosition} · '
                    'Ch. $numeral p. ${a.page + 1}',
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(a.body, style: text.bodyMedium),
                  if (!current)
                    Text(
                      'On an earlier version of Chapter $numeral',
                      key: Key('highlightStale-${a.id}'),
                      style: text.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            if (canDelete && a.authorUid == myUid && onDelete != null)
              IconButton(
                key: Key('deleteHighlight-${a.id}'),
                tooltip: 'Remove highlight',
                onPressed: () => onDelete!(a),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// The room's Highlights tab: who is writing a highlight comment, then the
/// list.
class HighlightsTab extends ConsumerWidget {
  const HighlightsTab({
    super.key,
    required this.defence,
    this.myUid,
    this.onSelect,
    this.onDelete,
  });

  final Defence defence;
  final String? myUid;
  final void Function(DefenceAnnotation)? onSelect;
  final void Function(DefenceAnnotation)? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationsAsync = ref.watch(defenceAnnotationsProvider(defence.id));
    final composing =
        ref.watch(defenceComposingProvider(defence.id)).valueOrNull ??
            const <DefenceComposing>[];
    final parts = ref
        .watch(manuscriptPartsProvider(
            (thesisId: defence.thesisId, type: defence.type)))
        .valueOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.md, AppTokens.sm, AppTokens.md, AppTokens.md),
      child: annotationsAsync.when(
        loading: () => const LoadingState(label: 'Loading highlights…'),
        error: (e, _) =>
            ErrorState(error: e, message: 'Could not load the highlights.'),
        data: (list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TypingLine(
              markers: composing,
              target: ComposingTarget.manuscript,
              myUid: myUid,
            ),
            HighlightsList(
              annotations: list,
              parts: parts,
              colours: highlightColours(defence: defence, annotations: list),
              numbers: highlightNumbers(list),
              myUid: myUid,
              canDelete: defence.status == DefenceStatus.inProgress,
              onSelect: onSelect,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the comment on a box just drawn. The trimmed text, or null if
/// cancelled. [onTyping] is told when the box gains and loses text, for the
/// typing indicator.
Future<String?> showHighlightComposer(
  BuildContext context, {
  void Function(bool typing)? onTyping,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _HighlightComposer(onTyping: onTyping),
  );
}

class _HighlightComposer extends StatefulWidget {
  const _HighlightComposer({this.onTyping});

  final void Function(bool typing)? onTyping;

  @override
  State<_HighlightComposer> createState() => _HighlightComposerState();
}

class _HighlightComposerState extends State<_HighlightComposer> {
  final _body = TextEditingController();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(_changed);
  }

  void _changed() {
    final now = _body.text.trim().isNotEmpty;
    if (now != _typing) {
      _typing = now;
      widget.onTyping?.call(now);
    }
    setState(() {});
  }

  @override
  void dispose() {
    if (_typing) widget.onTyping?.call(false);
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _body.text.trim();
    return AlertDialog(
      title: const Text('Comment on this passage'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('highlightBody'),
          controller: _body,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          maxLength: kAnnotationMaxLength,
          decoration: const InputDecoration(
              hintText: 'What should the group look at here?'),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelHighlight'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('saveHighlight'),
          onPressed: text.isEmpty ? null : () => Navigator.of(context).pop(text),
          child: const Text('Save highlight'),
        ),
      ],
    );
  }
}
