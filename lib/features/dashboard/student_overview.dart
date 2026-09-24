import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/needs_you_queue.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/overview_common.dart';
import 'package:ethesishub/features/dashboard/progress_rail.dart';
import 'package:ethesishub/features/notifications/notifications_screen.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The student's thesis desk.
///
/// Built around one object — the group's thesis — rather than a row of
/// counters: its identity and journey across the top, the next step and
/// the chapter register in the main column, and the people, the next
/// defence and recent decisions beside them.
class StudentOverview extends ConsumerWidget {
  const StudentOverview({super.key});

  /// The soonest defence that has not concluded. Sorted locally: the
  /// provider makes no ordering guarantee.
  static Defence? nextDefence(List<Defence> defences) {
    final open = defences.where((d) => !d.status.isTerminal).toList()
      ..sort((a, b) {
        final at = a.scheduledAt;
        final bt = b.scheduledAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
    return open.isEmpty ? null : open.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesisAsync = ref.watch(myThesisProvider);
    final needsYouAsync = ref.watch(studentNeedsYouProvider);
    final thesis = thesisAsync.valueOrNull;

    final header = DashboardHeader(
      office: 'Student researcher',
      summary: NeedsYouHeadline(
        items: needsYouAsync,
        suffix: 'your thesis desk',
      ),
      actions: [
        if (thesis != null)
          FilledButton.icon(
            key: const Key('openMyThesis'),
            onPressed: () => context.go('/thesis'),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Open thesis workspace'),
          ),
      ],
    );

    return KeyedSubtree(
      key: const Key('studentOverview'),
      child: thesisAsync.when(
        loading: () => const DashboardBody(children: [
          LoadingState.page(label: 'Loading your thesis desk…'),
        ]),
        error: (e, _) => DashboardBody(children: [
          header,
          ErrorState(error: e, message: 'Could not load your thesis.'),
        ]),
        data: (t) => t == null
            ? DashboardBody(children: [
                header,
                const _NoGroupYet(),
                NeedsYouQueue(
                  items: needsYouAsync,
                  emptyTitle: 'All caught up',
                  emptyMessage: 'Nothing needs your attention right now.',
                ),
              ])
            : _Desk(thesis: t, header: header),
      ),
    );
  }
}

class _Desk extends ConsumerWidget {
  const _Desk({required this.thesis, required this.header});

  final Thesis thesis;
  final Widget header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsYouAsync = ref.watch(studentNeedsYouProvider);
    final chaptersAsync = ref.watch(chaptersProvider(thesis.id));
    final defencesAsync = ref.watch(myDefencesProvider);

    return DashboardBody(children: [
      header,
      _ThesisHero(
        thesis: thesis,
        chapters: chaptersAsync.valueOrNull ?? const [],
        defences: defencesAsync.valueOrNull ?? const [],
      ),
      SplitColumns(
        primary: [
          NeedsYouQueue(
            items: needsYouAsync,
            emptyTitle: 'All caught up',
            emptyMessage: 'Nothing needs your attention right now. '
                'We will post here when an office acts on your thesis.',
          ),
          _ChapterRegister(thesis: thesis, chapters: chaptersAsync),
        ],
        secondary: [
          _AdviserPanel(thesis: thesis),
          _NextDefencePanel(defences: defencesAsync),
          const RecentNotificationsPanel(),
        ],
      ),
    ]);
  }
}

/// The thesis's identity and where it is on its journey.
class _ThesisHero extends StatelessWidget {
  const _ThesisHero({
    required this.thesis,
    required this.chapters,
    required this.defences,
  });

  final Thesis thesis;
  final List<ThesisChapter> chapters;
  final List<Defence> defences;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final stage = ProgressRail.stageFor(
      status: thesis.status,
      defences: defences,
      chapters: chapters,
    );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(thesis.status),
              Text(
                [thesis.program, thesis.academicYear]
                    .where((s) => s.isNotEmpty)
                    .join(', '),
                style: text.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.md - 4),
          Text(
            thesis.workingTitle,
            key: const Key('heroWorkingTitle'),
            style: text.headlineSmall,
          ),
          const SizedBox(height: AppTokens.xs),
          Text(
            StatusChip.detailFor(thesis.status),
            style: text.bodyMedium?.copyWith(color: p.muted),
          ),
          const SizedBox(height: AppTokens.lg),
          Divider(color: p.rule),
          const SizedBox(height: AppTokens.lg - 4),
          ProgressRail(
            status: thesis.status,
            defences: defences,
            chapters: chapters,
          ),
          if (thesis.status != ThesisStatus.archived) ...[
            const SizedBox(height: AppTokens.md),
            Text(
              'Now: ${ProgressRail.describe(stage)}.',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChapterRegister extends StatelessWidget {
  const _ChapterRegister({required this.thesis, required this.chapters});

  final Thesis thesis;
  final AsyncValue<List<ThesisChapter>> chapters;

  @override
  Widget build(BuildContext context) {
    final unlocked = thesis.status == ThesisStatus.titleApproved;
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    return Panel(
      title: 'Chapters',
      subtitle: unlocked
          ? 'Each chapter is reviewed by your adviser'
          : 'Opens once the Dean approves your title',
      icon: Icons.menu_book_outlined,
      flush: true,
      trailing: unlocked
          ? TextButton(
              key: const Key('studentOpenChapters'),
              onPressed: () =>
                  context.go('/thesis/chapters?id=${thesis.id}'),
              child: const Text('Manage'),
            )
          : null,
      child: chapters.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppTokens.md),
          child: LoadingState(),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: ErrorState(error: e, message: 'Could not load chapters.'),
        ),
        data: (list) {
          final byId = {for (final c in list) c.id: c};
          final approved =
              list.where((c) => c.status == ChapterStatus.approved).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.lg - 4, AppTokens.md, AppTokens.lg - 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: approved / 5),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 8,
                            color: Tone.endorsed.color(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.md),
                    Text('$approved of 5 approved', style: text.labelMedium),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.sm),
              for (final id in ChapterId.values)
                _ChapterLine(
                  id: id,
                  chapter: byId[id],
                  onTap: unlocked
                      ? () => context.push(
                          '/thesis/chapters/${id.value}?id=${thesis.id}')
                      : null,
                  muted: p.muted,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ChapterLine extends StatelessWidget {
  const _ChapterLine({
    required this.id,
    required this.chapter,
    required this.onTap,
    required this.muted,
  });

  final ChapterId id;
  final ThesisChapter? chapter;
  final VoidCallback? onTap;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = chapter;
    final parts = id.label.split(' — ');
    final row = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg - 4, vertical: AppTokens.sm + 2),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(parts.first, style: text.labelMedium),
          ),
          Expanded(
            child: Text(
              parts.length > 1 ? parts.last : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium,
            ),
          ),
          const SizedBox(width: AppTokens.sm),
          if (c == null)
            Text('Not uploaded', style: text.bodySmall)
          else
            ToneBadge(
              label: '${ChapterStatusWords.labelFor(c.status)} · '
                  'v${c.currentVersion}',
              tone: ChapterStatusWords.toneFor(c.status),
              icon: ChapterStatusWords.iconFor(c.status),
              dense: true,
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _AdviserPanel extends ConsumerWidget {
  const _AdviserPanel({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = thesis.adviserUid;
    final dirAsync = ref.watch(allDirectoryProvider);
    return Panel(
      title: 'Your adviser',
      icon: Icons.school_outlined,
      child: uid == null
          ? Text(
              thesis.status == ThesisStatus.draft
                  ? 'Not yet nominated. Nominate an adviser and panel from '
                      'your thesis workspace.'
                  : 'Not yet assigned.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : dirAsync.when(
              loading: () => const LoadingState(),
              error: (e, _) =>
                  ErrorState(error: e, message: 'Could not load names.'),
              data: (dir) {
                final entry = dir.where((d) => d.uid == uid).firstOrNull;
                return PersonLine(
                  name: entry?.fullName ?? 'Name unavailable',
                  role: entry?.specialization?.isNotEmpty == true
                      ? 'Adviser, ${entry!.specialization}'
                      : 'Adviser',
                );
              },
            ),
    );
  }
}

class _NextDefencePanel extends StatelessWidget {
  const _NextDefencePanel({required this.defences});

  final AsyncValue<List<Defence>> defences;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Panel(
      title: 'Next defence',
      icon: Icons.event_outlined,
      child: defences.when(
        loading: () => const LoadingState(),
        error: (e, _) =>
            ErrorState(error: e, message: 'Could not load defences.'),
        data: (list) {
          final next = StudentOverview.nextDefence(list);
          if (next == null) {
            return Text(
              'None scheduled. The Research Coordinator schedules pre-oral '
              'and final defences once your chapters are ready.',
              style: text.bodySmall,
            );
          }
          final at = next.scheduledAt;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push('/defence/room/${next.id}'),
            child: Row(
              children: [
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
                  decoration: BoxDecoration(
                    color: p.seal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(at == null ? '—' : Dates.monthShort(at),
                          style: text.labelSmall?.copyWith(color: p.seal)),
                      Text(at == null ? '?' : '${at.toLocal().day}',
                          style: text.headlineSmall
                              ?.copyWith(color: p.seal, height: 1.1)),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.md - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(next.type.label, style: text.titleMedium),
                      Text(
                        at == null
                            ? 'Date to be confirmed'
                            : '${Dates.weekday(at)}, ${Dates.time(at)}',
                        style: text.bodySmall,
                      ),
                      if (next.venue.isNotEmpty)
                        Text(next.venue, style: text.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.muted),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A student with no group: the three things that happen first, in order,
/// and the one button that starts them.
class _NoGroupYet extends StatelessWidget {
  const _NoGroupYet();

  static const _steps = [
    ('Create your group', 'Name your working title and list your members.'),
    ('Nominate an adviser and panel', 'Each nominee is asked to accept.'),
    ('Submit candidate titles', 'After the Dean approves the nomination.'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Panel(
      emphasis: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start your thesis', style: text.headlineSmall),
          const SizedBox(height: AppTokens.xs),
          Text(
            'Your group leader creates the thesis group. Everything else '
            'follows from it.',
            style: text.bodyMedium?.copyWith(color: p.muted),
          ),
          const SizedBox(height: AppTokens.lg),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.md - 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? p.seal : Colors.transparent,
                      border: i == 0 ? null : Border.all(color: p.rule),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: text.labelMedium?.copyWith(
                        color: i == 0
                            ? Theme.of(context).colorScheme.onPrimary
                            : p.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.md - 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_steps[i].$1, style: text.labelLarge),
                        Text(_steps[i].$2, style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppTokens.sm),
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            children: [
              FilledButton(
                key: const Key('overviewCreateThesis'),
                onPressed: () => context.go('/thesis/create'),
                child: const Text('Create thesis group'),
              ),
              OutlinedButton(
                onPressed: () => context.go('/archive'),
                child: const Text('Browse the archive'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
