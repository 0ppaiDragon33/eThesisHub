import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/config/advising.dart';
import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/party_popper_header.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/features/dashboard/switch_mode_notice.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Archived groups the adviser has removed from their own advisee list.
///
/// Kept on this device, per signed-in adviser. Removing only hides the row
/// here: the thesis, its adviser record and its archive entry are untouched,
/// and an archived thesis already stopped counting toward [kMaxAdvisees].
class HiddenAdviseesNotifier extends Notifier<Set<String>> {
  String get _key => 'hiddenAdvisees:${ref.read(signedInUidProvider) ?? ''}';

  @override
  Set<String> build() {
    ref.watch(signedInUidProvider);
    try {
      return (ref.read(sharedPrefsProvider).getStringList(_key) ??
              const <String>[])
          .toSet();
    } catch (_) {
      // No preferences store available: nothing is hidden.
      return <String>{};
    }
  }

  Future<void> hide(String thesisId) async {
    state = {...state, thesisId};
    try {
      await ref
          .read(sharedPrefsProvider)
          .setStringList(_key, state.toList());
    } catch (_) {
      // The row is still hidden for this session.
    }
  }
}

final hiddenAdviseesProvider =
    NotifierProvider<HiddenAdviseesNotifier, Set<String>>(
        HiddenAdviseesNotifier.new);

/// [myAdviseesProvider] without the archived groups the adviser removed.
final visibleAdviseesProvider = Provider<AsyncValue<List<Thesis>>>((ref) {
  final hidden = ref.watch(hiddenAdviseesProvider);
  return ref.watch(myAdviseesProvider).whenData((list) => [
        for (final t in list)
          if (!(t.status == ThesisStatus.archived && hidden.contains(t.id))) t,
      ]);
});

/// The adviser's roster: every thesis you advise, with each group's five
/// chapters shown as a row of marks and a count of what waits on you.
class AdviseesScreen extends ConsumerWidget {
  const AdviseesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adviseesAsync = ref.watch(visibleAdviseesProvider);
    final count = adviseesAsync.valueOrNull?.length;

    return PageShell(
      key: const Key('adviseesScreen'),
      maxWidth: AppTokens.measureWide,
      kicker: 'Adviser',
      title: 'My advisees',
      subtitle: count == null
          ? 'Each manuscript, for each thesis you advise.'
          : count == 1
              ? 'One group.'
              : '$count groups.',
      children: const [
        SwitchModeNotice(
          needed: FacultyMode.adviser,
          message: 'Switch to Adviser mode to use your advisees.',
        ),
        AdviseeRegister(),
      ],
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
    final adviseesAsync = ref.watch(visibleAdviseesProvider);

    return adviseesAsync.when(
      // Loading is never collapsed into "no advisees": that bug shipped
      // four times.
      loading: () => const LoadingState(label: 'Loading your advisees…'),
      error: (e, _) =>
          ErrorState(error: e, message: 'Could not load your advisees.'),
      data: (advisees) {
        if (advisees.isEmpty) {
          return const EmptyState(
            icon: Icons.school_outlined,
            title: 'No advisees yet',
            message: 'Theses you advise appear here once approved.',
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
    // A finished group has no chapters left to review: it gets a
    // congratulation instead of the review controls.
    if (thesis.status == ThesisStatus.archived) {
      return _ArchivedAdviseeRow(thesis: thesis);
    }
    final chaptersAsync = ref.watch(chaptersProvider(thesis.id));
    // Reviewing chapters and opening the title defense are adviser work. In
    // Panelist mode the row stays visible but does nothing; the notice at
    // the top of the screen offers the switch.
    final canAct = ref.watch(modeAllowsProvider(FacultyMode.adviser));
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    // At title defence there are no chapters yet; the defence is the work.
    final atTitleDefence = thesis.status == ThesisStatus.titlePendingDefence;
    void open() => context.push(atTitleDefence
        ? '/defence/${thesis.id}'
        : '/thesis/chapters?id=${thesis.id}');
    final VoidCallback? onOpen = canAct ? open : null;

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
      onTap: onOpen,
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
                  onPressed: onOpen,
                  child: const Text('Open title defense'),
                )
              : FilledButton.tonal(
                  key: Key('openChapters-${thesis.id}'),
                  // No faculty destination owns '/thesis/chapters', so it is
                  // pushed, leaving this list as the back stop.
                  onPressed: onOpen,
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

/// An advisee whose thesis has been archived: congratulates the adviser and
/// lets them take the group off their list. The first time such a row shows
/// in a session, in Adviser mode, it also opens a congratulations dialog
/// with party poppers.
class _ArchivedAdviseeRow extends ConsumerStatefulWidget {
  const _ArchivedAdviseeRow({required this.thesis});

  final Thesis thesis;

  // Per app session, so coming back to the list does not replay the dialog.
  static final Set<String> _celebrated = {};

  // Only one congratulations dialog at a time, so several archived groups
  // do not stack dialogs (and confetti) on top of each other.
  static bool _dialogOpen = false;

  @override
  ConsumerState<_ArchivedAdviseeRow> createState() =>
      _ArchivedAdviseeRowState();
}

class _ArchivedAdviseeRowState extends ConsumerState<_ArchivedAdviseeRow> {
  String get _title {
    final changed = widget.thesis.approvedTitleText;
    return (changed != null && changed.isNotEmpty)
        ? changed
        : widget.thesis.workingTitle;
  }

  @override
  void initState() {
    super.initState();
    _scheduleCelebrate();
  }

  void _scheduleCelebrate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCelebrate());
  }

  /// Opens the dialog at most once per group per session. Safe to call any
  /// number of times: it does nothing until every condition holds, so it is
  /// re-tried whenever the member's mode changes or finishes resolving.
  void _maybeCelebrate() {
    if (!mounted) return;
    final id = widget.thesis.id;
    if (_ArchivedAdviseeRow._celebrated.contains(id)) return;

    // Wait until the mode is actually known, so a member in Panelist mode is
    // never congratulated for an adviser's result in the first frames.
    if (!ref.read(effectiveFacultyModeProvider).hasValue ||
        !ref.read(facultyHoldsBothCapabilitiesProvider).hasValue) {
      return;
    }
    // In Panelist mode nothing here is theirs to act on. The dialog waits
    // for them to switch; the notice at the top of the screen offers it.
    if (!ref.read(modeAllowsProvider(FacultyMode.adviser))) return;

    // Another group's dialog is already up. Leave this one uncelebrated,
    // so it gets its turn the next time the list is opened.
    if (_ArchivedAdviseeRow._dialogOpen) return;

    _ArchivedAdviseeRow._celebrated.add(id);
    _ArchivedAdviseeRow._dialogOpen = true;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('adviseeCongratsDialog'),
        icon: PartyPopperHeader(
          center: Icon(
            Icons.emoji_events_rounded,
            size: 56,
            color: Tone.endorsed.color(dialogContext),
          ),
        ),
        title: const Text('Congratulations!'),
        content: Text(
          'Your advisees finished "$_title". They no longer count '
          'toward your limit of $kMaxAdvisees.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('adviseeCongratsView'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (mounted) context.push('/archive/$id');
            },
            child: const Text('View in the archive'),
          ),
        ],
      ),
    ).whenComplete(() {
      _ArchivedAdviseeRow._dialogOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Try again whenever the mode changes or finishes resolving, so
    // switching to Adviser mode is what brings the celebration up.
    ref.listen(effectiveFacultyModeProvider, (_, _) => _scheduleCelebrate());
    ref.listen(
      facultyHoldsBothCapabilitiesProvider,
      (_, _) => _scheduleCelebrate(),
    );
    final canAct = ref.watch(modeAllowsProvider(FacultyMode.adviser));

    final thesis = widget.thesis;
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final accent = Tone.endorsed.color(context);

    return Container(
      key: Key('advisee-${thesis.id}'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg - 4, vertical: AppTokens.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_events_rounded, size: 26, color: accent),
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Congratulations!',
                    key: Key('adviseeCongrats-${thesis.id}'),
                    style: text.titleMedium?.copyWith(color: accent)),
                const SizedBox(height: 2),
                Text(
                  'Your advisees finished "$_title". You can remove them '
                  'from your list; they no longer count toward your limit '
                  'of $kMaxAdvisees.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppTokens.sm),
                Wrap(
                  spacing: AppTokens.sm,
                  runSpacing: AppTokens.sm,
                  children: [
                    // Taking a group off the list is adviser work: disabled
                    // in Panelist mode. Reading the archive is not.
                    FilledButton.tonal(
                      key: Key('removeAdvisee-${thesis.id}'),
                      onPressed: canAct
                          ? () => ref
                              .read(hiddenAdviseesProvider.notifier)
                              .hide(thesis.id)
                          : null,
                      child: const Text('Remove from my advisees'),
                    ),
                    OutlinedButton(
                      key: Key('viewArchived-${thesis.id}'),
                      onPressed: () =>
                          context.push('/archive/${thesis.id}'),
                      child: const Text('View in the archive'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    // Two marks, "I–III" and "I–V": the adviser reviews one manuscript at
    // each stage. A thesis from before manuscripts, which has only separate
    // chapter records, keeps its five chapter marks instead. The strip
    // scales down to fit a narrow advisee card rather than overflowing.
    final marks = !byId.keys.any((id) => id.isManuscript) &&
            byId.keys.any((id) => !id.isManuscript)
        ? ChapterId.legacyChapters
        : ChapterId.manuscripts;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final id in marks)
          Builder(builder: (context) {
            final c = byId[id];
            final color = c == null
                ? p.rule
                : ChapterStatusWords.toneFor(c.status, adviser: true)
                    .color(context);
            final roman = id.mark;
            return Tooltip(
              message: c == null
                  ? '${id.label}: not uploaded'
                  : '${id.label}: '
                      '${ChapterStatusWords.labelFor(c.status, adviser: true)}',
              child: Container(
                width: id.isManuscript ? 52 : 30,
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