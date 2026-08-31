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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Brightness-aware like every other colour consumer in the app; the app
    // ships `themeMode: ThemeMode.system`.
    final dark = theme.brightness == Brightness.dark;
    final done = dark ? AppTokens.endorsedDark : AppTokens.endorsed;
    final here = dark ? AppTokens.sealDark : AppTokens.seal;
    final ahead = dark ? AppTokens.ruleDark : AppTokens.rule;
    // Archived is terminal: every stage is complete. Setting currentIndex
    // to values.length (past the last stage) makes all stages paint as done.
    final currentIndex = status == ThesisStatus.archived
        ? RailStage.values.length
        : RailStage.values.indexOf(current);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppTokens.md,
          horizontal: AppTokens.sm,
        ),
        child: Row(
          children: [
            for (final stage in RailStage.values)
              Expanded(
                key: Key('railStep-${stage.id}'),
                child: Column(
                  children: [
                    Container(
                      key: status != ThesisStatus.archived && stage == current
                          ? Key('railCurrent-${stage.id}')
                          : null,
                      width: status != ThesisStatus.archived && stage == current
                          ? 14
                          : 11,
                      height: status != ThesisStatus.archived && stage == current
                          ? 14
                          : 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (RailStage.values.indexOf(stage)) {
                          final i when i < currentIndex => done,
                          final i when i == currentIndex => here,
                          _ => ahead,
                        },
                      ),
                    ),
                    const SizedBox(height: AppTokens.xs),
                    Text(
                      stage.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            status != ThesisStatus.archived && stage == current
                                ? FontWeight.w700
                                : FontWeight.w400,
                        color: status != ThesisStatus.archived &&
                                stage == current
                            ? here
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
