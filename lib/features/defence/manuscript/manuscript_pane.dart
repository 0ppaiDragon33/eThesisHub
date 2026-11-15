import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/open_document.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Opens a chapter file the manuscript cannot draw (an old Word upload) in
/// the document viewer, which says it cannot be previewed and downloads it
/// from there.
Future<void> openChapterFile(
  BuildContext context,
  WidgetRef ref,
  ChapterVersion v,
) async {
  await openStoredDocument(context, ref, v.storagePath,
      label: 'Version ${v.version}');
}

/// The defence manuscript, framed and bound to one defence: its chapters,
/// its highlights and their colours.
class DefenceManuscriptPane extends ConsumerWidget {
  const DefenceManuscriptPane({
    super.key = const Key('manuscriptPane'),
    required this.defence,
    this.canHighlight = false,
    this.highlightClosedReason,
    this.onHighlightDrawn,
    this.controller,
  });

  final Defence defence;
  final bool canHighlight;
  final String? highlightClosedReason;
  final void Function(DrawnHighlight)? onHighlightDrawn;
  final ManuscriptController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final partsAsync = ref.watch(
      manuscriptPartsProvider((
        defenceId: defence.id,
        thesisId: defence.thesisId,
        type: defence.type,
      )),
    );
    final annotations =
        ref.watch(defenceAnnotationsProvider(defence.id)).valueOrNull ??
        const <DefenceAnnotation>[];
    final range = defence.type == DefenceType.preOral ? 'I–III' : 'I–V';

    final body = partsAsync.when(
      loading: () => const LoadingState(label: 'Loading the manuscript…'),
      error: (e, _) =>
          ErrorState(error: e, message: 'Could not load the chapters.'),
      data: (parts) => ManuscriptView(
        parts: parts,
        annotations: annotations,
        colours: highlightColours(defence: defence, annotations: annotations),
        numbers: highlightNumbers(annotations),
        canHighlight: canHighlight,
        highlightClosedReason: highlightClosedReason,
        onHighlightDrawn: onHighlightDrawn,
        onOpenFile: (v) => openChapterFile(context, ref, v),
        controller: controller,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        // Its own Material, so the text inside takes the theme's styles
        // wherever the pane is mounted, not the unstyled fallback a route
        // without a Scaffold would give it.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.md,
                  AppTokens.sm,
                  AppTokens.md,
                  AppTokens.sm,
                ),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_outlined, size: 18, color: p.muted),
                    const SizedBox(width: AppTokens.sm),
                    Text('Manuscript', style: text.titleSmall),
                    const SizedBox(width: AppTokens.sm),
                    Expanded(
                      child: Text(
                        'Chapters $range · approved versions',
                        style: text.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
