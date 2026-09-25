import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The adviser's roster: every thesis you advise, with each group's five
/// chapters shown as a row of marks and a count of what waits on you.
class AdviseesScreen extends ConsumerWidget {
  const AdviseesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adviseesAsync = ref.watch(myAdviseesProvider);
    final count = adviseesAsync.valueOrNull?.length;

    return PageShell(
      key: const Key('adviseesScreen'),
      maxWidth: AppTokens.measureWide,
      kicker: 'Adviser',
      title: 'My advisees',
      subtitle: count == null
          ? 'Chapters I–V for each thesis you advise.'
          : count == 1
              ? 'One group. Chapters I–V, and what waits on your review.'
              : '$count groups. Chapters I–V, and what waits on your review.',
      children: const [AdviseeRegister()],
    );
  }
}

/// The advisee register, reusable on the faculty overview with [limit].
class AdviseeRegister extends ConsumerWidget {
  const AdviseeRegister({super.key, this.limit, this.title});

  final int? limit;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adviseesAsync = ref.watch(myAdviseesProvider);

    return adviseesAsync.when(
      // Loading is never collapsed into "no advisees" — that bug shipped
      // four times.
      loading: () => const LoadingState(label: 'Loading your advisees…'),
      error: (e, _) =>
          ErrorState(error: e, message: 'Could not load your advisees.'),
      data: (advisees) {
        if (advisees.isEmpty) {
          return const EmptyState(
            icon: Icons.school_outlined,
            title: 'No advisees yet',
            message: 'Once a group nominates you as adviser and the Dean '
                'approves, their thesis appears here.',
          );
        }
        final shown = limit == null ? advisees : advisees.take(limit!).toList();
        return FadeIn(child: Panel(
          title: title,
          flush: true,
          trailing: limit != null && advisees.length > limit!
              ? TextButton(
                  onPressed: () => context.go('/advisees'),
                  child: Text('All ${advisees.length}'),
                )
              : null,
          child: Column(
            children: [for (final t in shown) AdviseeRow(thesis: t)],
          ),
        ));
      },
    );
  }
}

/// One advised thesis. Its own widget because each row watches its own
/// chapter stream.
class AdviseeRow extends ConsumerWidget {
  const AdviseeRow({super.key, required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider(thesis.id));
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    // At title defence there are no chapters yet; the defence is the work.
    final atTitleDefence = thesis.status == ThesisStatus.titlePendingDefence;
    void open() => context.push(atTitleDefence
        ? '/defence/${thesis.id}'
        : '/thesis/chapters?id=${thesis.id}');

    final awaitingText = chaptersAsync.when(
      // Never "0 awaiting" while loading.
      loading: () => 'Checking chapters…',
      error: (_, _) => 'Could not load this thesis\'s chapters.',
      data: (chapters) {
        final n =
            chapters.where((c) => c.status == ChapterStatus.submitted).length;
        return switch (n) {
          0 => 'Nothing awaiting review',
          1 => '1 chapter awaiting review',
          _ => '$n chapters awaiting review',
        };
      },
    );
    final awaiting = chaptersAsync.valueOrNull
            ?.where((c) => c.status == ChapterStatus.submitted)
            .length ??
        0;

    final marks = _ChapterMarks(chapters: chaptersAsync.valueOrNull);

    return InkWell(
      key: Key('advisee-${thesis.id}'),
      onTap: open,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.lg - 4, vertical: AppTokens.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.rule)),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 640;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(thesis.workingTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium),
              const SizedBox(height: 2),
              Text(
                [thesis.program, thesis.college]
                    .where((s) => s.isNotEmpty)
                    .join(', '),
                style: text.bodySmall,
              ),
              const SizedBox(height: AppTokens.sm),
              StatusChip(thesis.status, dense: true),
            ],
          );
          final work = Column(
            crossAxisAlignment:
                narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              marks,
              const SizedBox(height: AppTokens.xs + 2),
              Text(
                awaitingText,
                style: text.labelMedium?.copyWith(
                  color: awaiting > 0 ? p.seal : p.muted,
                ),
              ),
            ],
          );
          final button = atTitleDefence
              ? FilledButton(
                  key: Key('openTitleDefence-${thesis.id}'),
                  onPressed: open,
                  child: const Text('Open title defence'),
                )
              : FilledButton.tonal(
                  key: Key('openChapters-${thesis.id}'),
                  // No faculty destination owns '/thesis/chapters', so it is
                  // pushed, leaving this list as the back stop (D23).
                  onPressed: open,
                  child: const Text('Review chapters'),
                );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: AppTokens.md - 4),
                work,
                const SizedBox(height: AppTokens.md - 4),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: identity),
              const SizedBox(width: AppTokens.lg),
              Expanded(flex: 3, child: work),
              const SizedBox(width: AppTokens.lg),
              button,
            ],
          );
        }),
      ),
    );
  }
}

/// Five marks, one per chapter, each with a tooltip naming its state. The
/// count beside them says the same thing in words.
class _ChapterMarks extends StatelessWidget {
  const _ChapterMarks({required this.chapters});

  final List<ThesisChapter>? chapters;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final byId = {for (final c in chapters ?? const <ThesisChapter>[]) c.id: c};
    // The strip is a fixed five marks (~170px). In the advisee card it sits
    // in a flex column that can be narrower than that once the sidebar
    // claims its width, so it scales down to fit rather than overflowing —
    // all five marks stay visible, just smaller when space is tight.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final id in ChapterId.values)
          Builder(builder: (context) {
            final c = byId[id];
            final color = c == null
                ? p.rule
                : ChapterStatusWords.toneFor(c.status).color(context);
            final roman = id.label.split(' — ').first.replaceFirst(
                'Chapter ', '');
            return Tooltip(
              message: c == null
                  ? '${id.label}: not uploaded'
                  : '${id.label}: ${ChapterStatusWords.labelFor(c.status)}',
              child: Container(
                width: 30,
                height: 24,
                margin: const EdgeInsets.only(right: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c == null
                      ? Colors.transparent
                      : color.withValues(alpha: 0.14),
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  roman,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: c == null ? p.muted : color,
                      ),
                ),
              ),
            );
          }),
      ],
      ),
    );
  }
}
