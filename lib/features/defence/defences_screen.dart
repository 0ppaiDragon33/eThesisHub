import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defence_stage.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/features/defence/redefence_stage.dart';
import 'package:ethesishub/features/defence/title_defence_stage.dart';


/// The Defences destination, at '/defences?stage=…' (spec 2026-09-25 §6.1).
///
/// A stage switch reads **Title
/// defence | Pre-oral | Final defence | Re-defence**. In the app the stage is
/// part of the URL, so a dashboard or a notification can link straight to
/// one. The router hands it in as [initialStage], and switching stages goes
/// to the new URL. Standing alone (in a test), switching is local state.
///
/// With no stage named — the sidebar's bare '/defences' — the page opens on
/// the first stage where the reader has something open
/// ([defaultDefenceStageProvider]), choosing once, so work arriving later
/// never moves the tab under them.
///
/// Each stage is a list. The month-by-month view of the same defences is
/// the separate Calendar destination ('/calendar').
class DefencesScreen extends ConsumerStatefulWidget {
  const DefencesScreen({
    super.key,
    this.initialStage,
    this.title = 'Defences',
    this.subtitle =
        'Title defences, pre-oral and final defences, and re-defences.',
  });

  /// The stage the link named; null lets the page choose.
  final DefenceStage? initialStage;
  final String title;
  final String subtitle;

  @override
  ConsumerState<DefencesScreen> createState() => _DefencesScreenState();
}

class _DefencesScreenState extends ConsumerState<DefencesScreen> {
  /// Null until chosen: named by the link, picked by the reader, or settled
  /// once by [defaultDefenceStageProvider].
  late DefenceStage? _stage = widget.initialStage;

  @override
  void didUpdateWidget(covariant DefencesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStage != widget.initialStage) {
      _stage = widget.initialStage;
    }
  }

  void _selectStage(DefenceStage stage) {
    setState(() => _stage = stage);
    // `go`, not `push`: changing tabs is not a step back should undo.
    GoRouter.maybeOf(context)?.go(stage.route);
  }

  @override
  Widget build(BuildContext context) {
    // No stage named: take the automatic one the moment it is known, and
    // keep it (assigned once, not re-read), so later work never moves the
    // tab the reader is looking at.
    if (_stage == null) {
      final pick = ref.watch(defaultDefenceStageProvider).valueOrNull;
      if (pick == null) {
        return PageShell(
          key: const Key('defencesScreen'),
          maxWidth: AppTokens.measureWide,
          title: widget.title,
          subtitle: widget.subtitle,
          children: const [LoadingState(label: 'Loading your defences…')],
        );
      }
      _stage = pick;
    }
    final stage = _stage!;
    final counts = ref.watch(defenceStageCountsProvider);

    return PageShell(
      key: const Key('defencesScreen'),
      maxWidth: AppTokens.measureWide,
      title: widget.title,
      subtitle: widget.subtitle,
      children: [
        // The switch's own available width decides short vs. full labels --
        // NOT the window's Breakpoint. Between about 720 and 1050px the
        // window is medium, but this switch has nowhere near enough room for
        // four full labels with icons and counts, and the horizontal scroll
        // below is a last resort a mouse cannot drag, not a fix.
        LayoutBuilder(builder: (context, constraints) {
          final short = constraints.maxWidth < 760;
          return Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<DefenceStage>(
                key: const Key('defenceStageSwitch'),
                segments: [
                  for (final s in DefenceStage.values)
                    ButtonSegment(
                      value: s,
                      label:
                          Text(s.labelFor(counts[s] ?? 0, compact: short)),
                      icon: short ? null : Icon(s.icon),
                    ),
                ],
                selected: {stage},
                onSelectionChanged: (selection) =>
                    _selectStage(selection.first),
              ),
            ),
          );
        }),
        const Gap.lg(),
        switch (stage) {
          DefenceStage.title => const TitleDefenceStage(),
          DefenceStage.redefence => const RedefenceStage(),
          DefenceStage.preOral => const DefencesList(
              key: ValueKey('preOralList'),
              where: _preOral,
              emptyTitle: 'No pre-oral defences',
              emptyMessage: 'A pre-oral defence appears here once the '
                  'Coordinator schedules one you are part of.',
            ),
          DefenceStage.finalDefence => const DefencesList(
              key: ValueKey('finalList'),
              where: _final,
              emptyTitle: 'No final defences',
              emptyMessage: 'A final defence appears here once the '
                  'Coordinator schedules one you are part of.',
            ),
        },
      ],
    );
  }
}

bool _preOral(Defence d) => DefenceStage.preOral.includes(d);
bool _final(Defence d) => DefenceStage.finalDefence.includes(d);
