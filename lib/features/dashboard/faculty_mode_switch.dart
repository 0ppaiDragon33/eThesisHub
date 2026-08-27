import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';

/// The Adviser/Panelist switch, which used to live in
/// `faculty_dashboard.dart`'s app bar and now lives in the shell's
/// trailing slot — the same place, one level up, for every faculty route
/// rather than only the dashboard.
///
/// Renders nothing at all unless the member actually holds an adviser
/// position. A member with none is clamped to panelist by
/// [effectiveFacultyModeProvider], and a switch that could only ever move
/// them to an empty Advisees list is a control that does nothing.
///
/// The badge counts work waiting in the mode that is NOT in force, so a
/// member deep in one role can see the other filling up without switching
/// to look.
class FacultyModeSwitch extends ConsumerWidget {
  const FacultyModeSwitch({super.key, required this.location});

  /// Where the reader is, so a mode change can move them off a screen the
  /// other mode does not have. Advisees and Panels are separate routes
  /// now, so staying put would leave a panelist reading the advisee list.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeAsync = ref.watch(effectiveFacultyModeProvider);
    final holdsAdviserPositions =
        (ref.watch(adviserPositionCountProvider).valueOrNull ?? 0) > 0;
    final pendingElsewhere =
        ref.watch(pendingInOtherModeProvider).valueOrNull ?? 0;

    final mode = modeAsync.valueOrNull;
    if (mode == null || !holdsAdviserPositions) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Badge(
        isLabelVisible: pendingElsewhere > 0,
        label: Text('$pendingElsewhere'),
        child: SegmentedButton<FacultyMode>(
          segments: const [
            ButtonSegment(value: FacultyMode.adviser, label: Text('Adviser')),
            ButtonSegment(value: FacultyMode.panelist, label: Text('Panelist')),
          ],
          selected: {mode},
          onSelectionChanged: (selection) {
            final next = selection.first;
            ref.read(facultyModeProvider.notifier).set(next);
            // Only when standing on the other mode's own screen. Flipping
            // the mode from, say, a chapter should change what the sidebar
            // offers — not teleport the reader out of what they were
            // reading.
            if (location == '/advisees' || location == '/panels') {
              context.go(next == FacultyMode.adviser ? '/advisees' : '/panels');
            }
          },
        ),
      ),
    );
  }
}
