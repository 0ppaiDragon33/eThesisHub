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
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The manuscript for one thesis, whether or not it has been uploaded:
/// Chapters I–III before the pre-oral, Chapters I–V after.
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
  /// bar, a sidebar and a way back, which is what the old `embedded` flag
  /// existed to arrange when a dashboard was hosting this screen, and what
  /// nothing arranged when the router was.
  Widget _framed(List<Widget> children) => PageShell(children: children);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesisAsync = ref.watch(thesisByIdProvider(thesisId));
    final chaptersAsync = ref.watch(chaptersProvider(thesisId));
    final me = ref.watch(currentUserProvider).valueOrNull;

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
    // The adviser of this thesis sees it from their own seat. Fail closed:
    // anyone not proven to be the adviser gets the group's view.
    final isAdviser = me != null && thesis.adviserUid == me.uid;
    if (thesis.status != ThesisStatus.titleApproved) {
      return _framed([
        EmptyState(
          key: const Key('notUnlocked'),
          icon: Icons.lock_outline,
          title: 'Chapters are not open yet',
          message: isAdviser
              ? 'The group can upload once the Dean approves their title.'
              : 'Chapters can be uploaded once the Dean has approved '
                  'your title.',
        ),
      ]);
    }

    // Checked separately from the thesis stream: while chapters are still
    // loading, `valueOrNull ?? []` used to read as "nothing uploaded yet",
    // which is indistinguishable from a group that genuinely has not
    // started. On error, the same fallback drew all five rows "Not started"
    // directly beneath a banner saying the chapters could not be loaded,
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
    // The full manuscript replaces the proposal one once this thesis's
    // pre-oral is passed. Taken as not yet passed while the defenses are
    // still loading.
    final preOralPassed = passedPreOral(
            ref.watch(myDefencesProvider).valueOrNull ?? const [],
            thesisId) !=
        null;
    // ONE manuscript at a time: Chapters I-III first, then I-V, never five
    // separate rows.
    final shelf =
        manuscriptShelf(preOralPassed: preOralPassed, uploaded: uploaded.keys);
    final text = Theme.of(context).textTheme;

    Widget entry(ChapterId id) => _ChapterEntry(
          key: Key('chapterRow-${id.value}'),
          id: id,
          chapter: uploaded[id],
          adviser: isAdviser,
          onTap: () =>
              context.push('/thesis/chapters/${id.value}?id=$thesisId'),
        );

    final range =
        shelf.current == ChapterId.manuscriptFinal ? 'I to V' : 'I to III';
    final authors = [
      if ((thesis.leaderName ?? '').trim().isNotEmpty) thesis.leaderName!.trim(),
      ...thesis.memberNames,
    ];
    final waiting = uploaded[shelf.current];
    final waitingOnAdviser =
        isAdviser && waiting?.status == ChapterStatus.submitted;

    return PageShell(
      key: const Key('chaptersScreen'),
      kicker: thesis.workingTitle,
      title: isAdviser ? 'Review manuscript' : 'Manuscript',
      subtitle: isAdviser
          ? (authors.isEmpty ? 'Chapters $range' : authors.join(', '))
          : 'Upload Chapters $range as one file.',
      children: [
        // The adviser's cue: a version is waiting on them.
        if (waitingOnAdviser) ...[
          Panel(
            key: const Key('reviewWaiting'),
            emphasis: true,
            icon: Icons.rate_review_outlined,
            title: 'Waiting for your review',
            child: Row(
              children: [
                Expanded(
                  child: Text('Version ${waiting!.currentVersion} is with you.',
                      style: text.bodyMedium),
                ),
                const SizedBox(width: AppTokens.md),
                FilledButton(
                  key: const Key('reviewNow'),
                  onPressed: () => context.push(
                      '/thesis/chapters/${shelf.current.value}?id=$thesisId'),
                  child: const Text('Review now'),
                ),
              ],
            ),
          ),
          const Gap.md(),
        ],
        Panel(
          flush: true,
          child: Column(children: [entry(shelf.current)]),
        ),
        if (!isAdviser &&
            !preOralPassed &&
            shelf.current == ChapterId.manuscriptProposal) ...[
          const Gap.sm(),
          Text(
            'After the pre-oral defense, this becomes Chapters I to V.',
            key: const Key('manuscriptNextNote'),
            style: text.bodySmall,
          ),
        ],
        // The proposal manuscript stays on record once the full one takes
        // over: its versions and the adviser's feedback are history.
        if (shelf.earlier != null) ...[
          const Gap.lg(),
          Text(isAdviser ? 'Before the pre-oral' : 'Before your pre-oral',
              style: text.titleSmall),
          const Gap.sm(),
          Panel(flush: true, child: Column(children: [entry(shelf.earlier!)])),
        ],
        // Uploaded chapter by chapter, from before manuscripts: still on
        // file and still counted, so still reachable.
        if (shelf.legacy.isNotEmpty) ...[
          const Gap.lg(),
          Text('Earlier chapter uploads', style: text.titleSmall),
          const Gap.sm(),
          Panel(
            flush: true,
            child: Column(children: [for (final id in shelf.legacy) entry(id)]),
          ),
        ],
      ],
    );
  }
}

class _ChapterEntry extends StatelessWidget {
  const _ChapterEntry({
    super.key,
    required this.id,
    required this.chapter,
    required this.onTap,
    this.adviser = false,
  });

  final ChapterId id;
  final ThesisChapter? chapter;
  final VoidCallback onTap;

  /// Worded and coloured for the adviser rather than the group.
  final bool adviser;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final c = chapter;
    final tone = c == null
        ? Tone.neutral
        : ChapterStatusWords.toneFor(c.status, adviser: adviser);

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
              // Wide enough for "I–III" and "I–V" as well as a single
              // numeral.
              width: id.isManuscript ? 56 : 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.color(context).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                id.mark,
                style: text.titleMedium?.copyWith(color: tone.color(context)),
              ),
            ),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(id.heading, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    c == null
                        ? (adviser ? 'Not uploaded yet' : 'Not started')
                        : '${ChapterStatusWords.detailFor(c.status, adviser: adviser)} '
                            'Version ${c.currentVersion}.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.sm),
            if (c != null)
              ToneBadge(
                label: ChapterStatusWords.labelFor(c.status, adviser: adviser),
                tone: tone,
                icon: ChapterStatusWords.iconFor(c.status, adviser: adviser),
                dense: true,
              ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}
