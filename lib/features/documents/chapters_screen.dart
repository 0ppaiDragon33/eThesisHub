import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
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
    final approved =
        uploaded.values.where((c) => c.status == ChapterStatus.approved).length;
    final waiting =
        uploaded.values.where((c) => c.status == ChapterStatus.submitted).length;
    final text = Theme.of(context).textTheme;

    return PageShell(
      key: const Key('chaptersScreen'),
      kicker: thesis.workingTitle,
      title: 'Chapters',
      subtitle: 'Each chapter goes to the adviser for review. Every upload is '
          'kept, so nothing is ever overwritten.',
      children: [
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$approved of 5 approved', style: text.titleMedium),
                    const SizedBox(height: AppTokens.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: approved / 5,
                        minHeight: 8,
                        color: Tone.endorsed.color(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$waiting', style: text.headlineSmall),
                  Text('with the adviser', style: text.bodySmall),
                ],
              ),
            ],
          ),
        ),
        const Gap.md(),
        Panel(
          flush: true,
          child: Column(
            children: [
              for (var i = 0; i < ChapterId.values.length; i++)
                _ChapterEntry(
                  key: Key('chapterRow-${ChapterId.values[i].value}'),
                  number: i + 1,
                  id: ChapterId.values[i],
                  chapter: uploaded[ChapterId.values[i]],
                  onTap: () => context.push(
                      '/thesis/chapters/${ChapterId.values[i].value}'
                      '?id=$thesisId'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChapterEntry extends StatelessWidget {
  const _ChapterEntry({
    super.key,
    required this.number,
    required this.id,
    required this.chapter,
    required this.onTap,
  });

  final int number;
  final ChapterId id;
  final ThesisChapter? chapter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final c = chapter;
    final parts = id.label.split(' — ');
    final tone = c == null ? Tone.neutral : ChapterStatusWords.toneFor(c.status);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.lg - 4, vertical: AppTokens.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.rule)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.color(context).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                parts.first.replaceFirst('Chapter ', ''),
                style: text.titleMedium?.copyWith(color: tone.color(context)),
              ),
            ),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(parts.length > 1 ? parts.last : id.label,
                      style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    c == null
                        ? 'Not started'
                        : '${ChapterStatusWords.detailFor(c.status)} '
                            'Version ${c.currentVersion}.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.sm),
            if (c != null)
              ToneBadge(
                label: ChapterStatusWords.labelFor(c.status),
                tone: tone,
                icon: ChapterStatusWords.iconFor(c.status),
                dense: true,
              ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}
