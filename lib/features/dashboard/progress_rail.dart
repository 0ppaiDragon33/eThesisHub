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

class ProgressRail extends StatefulWidget {
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
  }) => switch (status) {
    ThesisStatus.draft => RailStage.draft,
    ThesisStatus.nominationPendingConforme ||
    ThesisStatus.nominationPendingCoordinator ||
    ThesisStatus.nominationPendingDean => RailStage.nomination,
    ThesisStatus.nominationApproved ||
    ThesisStatus.titlePendingDefence ||
    ThesisStatus.titleRejected => RailStage.title,
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
    final counted = defences.where((d) => d.status != DefenceStatus.cancelled);
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
    RailStage.nomination =>
      'Adviser and panel accept; Coordinator and '
          'Dean sign off',
    RailStage.title => 'Candidate titles go before the panel',
    RailStage.chapters => 'Chapters I–V, reviewed by the adviser',
    RailStage.preOral => 'Proposal defended before the panel',
    RailStage.finalDefence => 'Final defence, then the archive',
  };

  /// A comfortable width for one stage — wide enough that its label sits on a
  /// single line. Six of these is the rail's natural width; below it, the row
  /// scrolls sideways rather than squeezing the labels into stacks.
  static const double _stepWidth = 96;

  @override
  State<ProgressRail> createState() => _ProgressRailState();
}

class _ProgressRailState extends State<ProgressRail> {
  final _controller = ScrollController();
  bool _scrolled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleScrollToCurrent();
  }

  @override
  void didUpdateWidget(covariant ProgressRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current ||
        oldWidget.status != widget.status) {
      _scrolled = false;
      _scheduleScrollToCurrent();
    }
  }

  void _scheduleScrollToCurrent() {
    if (_scrolled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  void _scrollToCurrent() {
    if (!mounted || !_controller.hasClients) return;
    if (_controller.position.maxScrollExtent <= 0) return;

    final archived = widget.status == ThesisStatus.archived;
    final currentIndex = archived
        ? RailStage.values.length - 1
        : RailStage.values.indexOf(widget.current);

    final viewport = _controller.position.viewportDimension;
    final target =
        (currentIndex * ProgressRail._stepWidth) -
        (viewport / 2) +
        (ProgressRail._stepWidth / 2);

    _scrolled = true;
    _controller.animateTo(
      target.clamp(0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final archived = widget.status == ThesisStatus.archived;
    final currentIndex = archived
        ? RailStage.values.length
        : RailStage.values.indexOf(widget.current);

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
        ),
    ];

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final s in steps) Expanded(child: s)],
    );

    return Semantics(
      label: archived
          ? 'Thesis journey: every stage complete'
          : 'Thesis journey: stage ${currentIndex + 1} of '
                '${RailStage.values.length}, ${widget.current.label}',
      // Always a left-to-right stepper. When the six stages fit, they share
      // the width evenly; when they do not (a phone), the rail scrolls
      // sideways at their natural width, auto-centred on the current stage,
      // with a soft edge fade so a cut-off step reads as "more here" rather
      // than a hard clip.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final natural = RailStage.values.length * ProgressRail._stepWidth;
          if (constraints.maxWidth >= natural) return row;
          return ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.04, 0.92, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: natural, child: row),
            ),
          );
        },
      ),
    );
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
  });

  final RailStage stage;
  final int number;
  final _StepState state;
  final bool first;
  final bool last;

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
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stage.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelLarge?.copyWith(
            color: state == _StepState.ahead ? muted : null,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        Text(
          stateWord,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelSmall?.copyWith(
            color: switch (state) {
              _StepState.done => done,
              _StepState.current => here,
              _StepState.ahead => muted,
            },
          ),
        ),
      ],
    );

    Color lineColor(bool before) {
      if (before) return state == _StepState.ahead ? rule : done;
      return state == _StepState.done ? done : rule;
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
