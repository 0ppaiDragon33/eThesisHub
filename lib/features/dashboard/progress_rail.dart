import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

/// The six stages a thesis passes through, and which one it is at.
///
/// A student's real question is "where are we and what is next", which a
/// status chip answers only narrowly — it names the current state without
/// showing the road. This is the one element of the dashboard with no
/// equivalent in the reference design, and it is here because the lifecycle
/// is the thing students ask their adviser about most.
enum RailStage {
  draft('draft', 'Draft'),
  nomination('nomination', 'Nomination'),
  title('title', 'Title'),
  chapters('chapters', 'Chapters'),
  preOral('preOral', 'Pre-oral'),
  finalDefence('final', 'Final');

  const RailStage(this.id, this.label);
  final String id;
  final String label;
}

class ProgressRail extends StatelessWidget {
  const ProgressRail({
    super.key,
    required this.status,
    this.defences = const [],
    this.chapters = const [],
  });

  final ThesisStatus status;

  /// Every defence on this thesis, not a pre-filtered "has one" flag.
  ///
  /// An earlier version took `hasDefence: defences.isNotEmpty`, which meant
  /// a **final** defence rendered as "Pre-oral" (leaving [
  /// RailStage.finalDefence] unreachable dead code) and a **cancelled** one
  /// still pushed the rail forward. A student who had finished everything
  /// saw the same rail as one whose pre-oral had been called off.
  final List<Defence> defences;

  /// The thesis's chapters. Spec §6.1 derives the stage past `titleApproved`
  /// from "chapter and defence state", and this is the chapter half: a
  /// defence examines chapter work, so with no chapter on file at all the
  /// rail holds at Chapters rather than claiming a defence stage off a
  /// single stray record.
  final List<ThesisChapter> chapters;

  RailStage get current =>
      stageFor(status: status, defences: defences, chapters: chapters);

  /// Static and pure so the derivation can be tested without a widget tree.
  static RailStage stageFor({
    required ThesisStatus status,
    List<Defence> defences = const [],
    List<ThesisChapter> chapters = const [],
  }) =>
      switch (status) {
        ThesisStatus.draft => RailStage.draft,
        ThesisStatus.nominationPendingConforme ||
        ThesisStatus.nominationPendingCoordinator ||
        ThesisStatus.nominationPendingDean =>
          RailStage.nomination,
        ThesisStatus.nominationApproved ||
        ThesisStatus.titlePendingDefence ||
        ThesisStatus.titleRejected =>
          RailStage.title,
        ThesisStatus.titleApproved => _afterTitle(defences, chapters),
        ThesisStatus.archived => RailStage.finalDefence,
      };

  /// `titleApproved` is the one status that covers three rail stages, so it
  /// is the only one that reads defence and chapter state.
  ///
  /// The filter is `!= cancelled` rather than `!isTerminal`: a cancelled
  /// defence is a record struck out — a duplicate, or one called off — and
  /// must not advance anything, while a **completed** one is the opposite,
  /// proof the stage was actually reached. Dropping completed defences too
  /// would send a group that had finished its final defence back to
  /// "Chapters".
  static RailStage _afterTitle(
    List<Defence> defences,
    List<ThesisChapter> chapters,
  ) {
    if (chapters.isEmpty) return RailStage.chapters;
    final counted =
        defences.where((d) => d.status != DefenceStatus.cancelled);
    if (counted.any((d) => d.type == DefenceType.final_)) {
      return RailStage.finalDefence;
    }
    if (counted.any((d) => d.type == DefenceType.preOral)) {
      return RailStage.preOral;
    }
    return RailStage.chapters;
  }

  /// One sentence per stage, for the reader who is standing on it.
  static String describe(RailStage stage) => switch (stage) {
        RailStage.draft => 'Group formed, working title named',
        RailStage.nomination => 'Adviser and panel accept; Coordinator and '
            'Dean sign off',
        RailStage.title => 'Candidate titles go before the panel',
        RailStage.chapters => 'Chapters I–V, reviewed by the adviser',
        RailStage.preOral => 'Proposal defended before the panel',
        RailStage.finalDefence => 'Final defence, then the archive',
      };

  @override
  Widget build(BuildContext context) {
    final archived = status == ThesisStatus.archived;
    final currentIndex = archived
        ? RailStage.values.length
        : RailStage.values.indexOf(current);

    return LayoutBuilder(builder: (context, constraints) {
      final vertical = constraints.maxWidth < 560;
      final steps = [
        for (var i = 0; i < RailStage.values.length; i++)
          _JourneyStep(
            key: Key('railStep-${RailStage.values[i].id}'),
            stage: RailStage.values[i],
            number: i + 1,
            state: i < currentIndex
                ? _StepState.done
                : i == currentIndex
                    ? _StepState.current
                    : _StepState.ahead,
            first: i == 0,
            last: i == RailStage.values.length - 1,
            vertical: vertical,
          ),
      ];
      return Semantics(
        label: archived
            ? 'Thesis journey: every stage complete'
            : 'Thesis journey: stage ${currentIndex + 1} of '
                '${RailStage.values.length}, ${current.label}',
        child: vertical
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: steps,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final s in steps) Expanded(child: s)],
              ),
      );
    });
  }
}

enum _StepState { done, current, ahead }

class _JourneyStep extends StatelessWidget {
  const _JourneyStep({
    super.key,
    required this.stage,
    required this.number,
    required this.state,
    required this.first,
    required this.last,
    required this.vertical,
  });

  final RailStage stage;
  final int number;
  final _StepState state;
  final bool first;
  final bool last;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final dark = theme.brightness == Brightness.dark;
    final done = dark ? AppTokens.endorsedDark : AppTokens.endorsed;
    final here = dark ? AppTokens.sealDark : AppTokens.seal;
    final rule = dark ? AppTokens.ruleDark : AppTokens.rule;
    final muted = dark ? AppTokens.inkMutedDark : AppTokens.inkMuted;
    final paper = dark ? AppTokens.surfaceDark : AppTokens.paper;
    final isCurrent = state == _StepState.current;

    final node = AnimatedContainer(
      key: isCurrent ? Key('railCurrent-${stage.id}') : null,
      duration: const Duration(milliseconds: 300),
      width: isCurrent ? 34 : 28,
      height: isCurrent ? 34 : 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (state) {
          _StepState.done => done,
          _StepState.current => here,
          _StepState.ahead => paper,
        },
        border: state == _StepState.ahead
            ? Border.all(color: rule, width: 1.5)
            : null,
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: here.withValues(alpha: 0.25),
                  blurRadius: 0,
                  spreadRadius: 5,
                ),
              ]
            : null,
      ),
      child: state == _StepState.done
          ? Icon(Icons.check_rounded, size: 16, color: paper)
          : Text(
              '$number',
              style: text.labelMedium?.copyWith(
                color: isCurrent ? paper : muted,
              ),
            ),
    );

    final stateWord = switch (state) {
      _StepState.done => 'Done',
      _StepState.current => 'Current stage',
      _StepState.ahead => 'Ahead',
    };

    final words = Column(
      crossAxisAlignment:
          vertical ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stage.label,
          textAlign: vertical ? TextAlign.start : TextAlign.center,
          style: text.labelLarge?.copyWith(
            color: state == _StepState.ahead ? muted : null,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        Text(
          stateWord,
          textAlign: vertical ? TextAlign.start : TextAlign.center,
          style: text.labelSmall?.copyWith(
            color: switch (state) {
              _StepState.done => done,
              _StepState.current => here,
              _StepState.ahead => muted,
            },
          ),
        ),
        if (isCurrent && vertical) ...[
          const SizedBox(height: 2),
          Text(ProgressRail.describe(stage), style: text.bodySmall),
        ],
      ],
    );

    Color lineColor(bool before) {
      if (before) return state == _StepState.ahead ? rule : done;
      return state == _StepState.done ? done : rule;
    }

    if (vertical) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  SizedBox(
                    height: 6,
                    child: first
                        ? null
                        : Container(width: 2, color: lineColor(true)),
                  ),
                  node,
                  Expanded(
                    child: last
                        ? const SizedBox()
                        : Container(width: 2, color: lineColor(false)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.sm + 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    top: 8, bottom: last ? 0 : AppTokens.md),
                child: words,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: first
                    ? const SizedBox()
                    : Container(height: 2, color: lineColor(true)),
              ),
              node,
              Expanded(
                child: last
                    ? const SizedBox()
                    : Container(height: 2, color: lineColor(false)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: words,
        ),
      ],
    );
  }
}
