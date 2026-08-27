import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Chapters I–V for one thesis, whether or not any have been uploaded.
class ChaptersScreen extends ConsumerWidget {
  const ChaptersScreen({
    super.key,
    required this.thesisId,
  });

  final String thesisId;

  /// Every state renders inside this frame.
  ///
  /// No Scaffold and no AppBar of its own any more: the app shell supplies
  /// both for every signed-in route, so a refusal here still has an app
  /// bar, a sidebar and a way back — which is what the old `embedded` flag
  /// existed to arrange when a dashboard was hosting this screen, and what
  /// nothing arranged when the router was.
  Widget _framed(List<Widget> children) => PageShell(children: children);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesisAsync = ref.watch(thesisByIdProvider(thesisId));
    final chaptersAsync = ref.watch(chaptersProvider(thesisId));

    if (thesisAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading your thesis…')]);
    }
    if (thesisAsync.hasError) {
      return _framed([
        ErrorState(
          error: thesisAsync.error,
          message: 'Could not load this thesis.',
        ),
      ]);
    }
    final thesis = thesisAsync.valueOrNull;
    if (thesis == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Thesis not found',
          message: 'This thesis no longer exists, or it belongs to another '
              'group.',
        ),
      ]);
    }
    if (thesis.status != ThesisStatus.titleApproved) {
      return _framed(const [
        EmptyState(
          key: Key('notUnlocked'),
          icon: Icons.lock_outline,
          title: 'Chapters are not open yet',
          message: 'Chapters can be uploaded once the Dean has approved '
              'your title.',
        ),
      ]);
    }

    // Checked separately from the thesis stream: while chapters are still
    // loading, `valueOrNull ?? []` used to read as "nothing uploaded yet",
    // which is indistinguishable from a group that genuinely has not
    // started. On error, the same fallback drew all five rows "Not started"
    // directly beneath a banner saying the chapters could not be loaded —
    // two contradictory claims on screen at once.
    if (chaptersAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading your chapters…')]);
    }
    if (chaptersAsync.hasError) {
      return _framed([
        ErrorState(
          error: chaptersAsync.error,
          message: 'Could not load your chapters.',
        ),
      ]);
    }

    final uploaded = {
      for (final c in chaptersAsync.valueOrNull ?? const <ThesisChapter>[])
        c.id: c,
    };
    final brightness = Theme.of(context).brightness;

    final page = PageShell(
      key: const Key('chaptersScreen'),
        title: 'Chapters',
        subtitle: 'Upload each chapter for your adviser to review. Every '
            'upload is kept, so nothing is ever overwritten.',
        children: [
          for (final id in ChapterId.values)
            Card(
              key: Key('chapterRow-${id.value}'),
              child: ListTile(
                title: Text(id.label),
                subtitle: Text(uploaded[id] == null
                    ? 'Not started'
                    : '${ChapterStatusWords.labelFor(uploaded[id]!.status)}'
                        ' · Version ${uploaded[id]!.currentVersion}'),
                subtitleTextStyle: uploaded[id] == null
                    ? null
                    : Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ChapterStatusWords.colorFor(
                            uploaded[id]!.status, brightness)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(
                    '/thesis/chapters/${id.value}?id=$thesisId'),
              ),
            ),
        ],
    );

    return page;
  }
}
