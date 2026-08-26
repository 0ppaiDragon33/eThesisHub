import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
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
    this.hasDefence = false,
  });

  final ThesisStatus status;
  final bool hasDefence;

  RailStage get current => switch (status) {
        ThesisStatus.draft => RailStage.draft,
        ThesisStatus.nominationPendingConforme ||
        ThesisStatus.nominationPendingCoordinator ||
        ThesisStatus.nominationPendingDean =>
          RailStage.nomination,
        ThesisStatus.nominationApproved ||
        ThesisStatus.titlePendingDefence ||
        ThesisStatus.titleRejected =>
          RailStage.title,
        ThesisStatus.titleApproved =>
          hasDefence ? RailStage.preOral : RailStage.chapters,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = RailStage.values.indexOf(current);

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
                      key: stage == current
                          ? Key('railCurrent-${stage.id}')
                          : null,
                      width: stage == current ? 14 : 11,
                      height: stage == current ? 14 : 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (RailStage.values.indexOf(stage)) {
                          final i when i < currentIndex => AppTokens.endorsed,
                          final i when i == currentIndex => AppTokens.seal,
                          _ => AppTokens.rule,
                        },
                      ),
                    ),
                    const SizedBox(height: AppTokens.xs),
                    Text(
                      stage.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: stage == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: stage == current
                            ? AppTokens.seal
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
