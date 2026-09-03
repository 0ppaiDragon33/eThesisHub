import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/app_shell.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';

/// The Adviser/Panelist switch, which used to live in
/// `faculty_dashboard.dart`'s app bar and now lives in the shell's
/// trailing slot — the same place, one level up, for every faculty route
/// rather than only the dashboard.
///
/// Renders nothing at all unless the member holds BOTH capabilities --
/// [facultyHoldsBothCapabilitiesProvider], the union of designation and
/// positions actually held (spec D30). A member with only one capability is
/// clamped to it by [effectiveFacultyModeProvider], and a switch that could
/// only ever move them to a destination they cannot reach is a control that
/// does nothing.
///
/// The badge counts work waiting in the mode that is NOT in force, so a
/// member deep in one role can see the other filling up without switching
/// to look.
///
/// Below `AppShell.railBreakpoint`, the full two-segment `SegmentedButton`
/// is replaced with a single icon button that toggles mode. The app bar on
/// a narrow screen already carries the hamburger, an optional back
/// control, and this widget's own badge; at 360dp — one of the commonest
/// Android widths — the labelled segmented button was wide enough by
/// itself to overflow the bar by more than a pixel, and a Badge's label
/// only grows that once `pendingElsewhere` is nonzero. An icon-only toggle
/// carries the same information (current mode, tap to switch, badge count)
/// in roughly a fifth of the width, and the wide rail branch — which has
/// an entire row's worth of space regardless of how many destinations it
/// lists — keeps the labelled version, since nothing there is tight.
class FacultyModeSwitch extends ConsumerWidget {
  const FacultyModeSwitch({super.key, required this.location});

  /// Where the reader is, so a mode change can move them off a screen the
  /// other mode does not have. Advisees and Panels are separate routes
  /// now, so staying put would leave a panelist reading the advisee list.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeAsync = ref.watch(effectiveFacultyModeProvider);
    final bothCapable =
        ref.watch(facultyHoldsBothCapabilitiesProvider).valueOrNull ?? false;
    final pendingElsewhere =
        ref.watch(pendingInOtherModeProvider).valueOrNull ?? 0;

    final mode = modeAsync.valueOrNull;
    if (mode == null || !bothCapable) return const SizedBox.shrink();

    void select(FacultyMode next) {
      ref.read(facultyModeProvider.notifier).set(next);
      // Only when standing on the other mode's own screen. Flipping
      // the mode from, say, a chapter should change what the sidebar
      // offers — not teleport the reader out of what they were
      // reading.
      if (location == '/advisees' || location == '/panels') {
        context.go(next == FacultyMode.adviser ? '/advisees' : '/panels');
      }
    }

    final narrow =
        MediaQuery.sizeOf(context).width < AppShell.railBreakpoint;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Badge(
        isLabelVisible: pendingElsewhere > 0,
        label: Text('$pendingElsewhere'),
        child: narrow
            ? IconButton(
                key: const Key('facultyModeCompact'),
                icon: Icon(mode == FacultyMode.adviser
                    ? Icons.school_outlined
                    : Icons.forum_outlined),
                tooltip: mode == FacultyMode.adviser
                    ? 'Adviser mode — tap to switch to Panelist'
                    : 'Panelist mode — tap to switch to Adviser',
                onPressed: () => select(mode == FacultyMode.adviser
                    ? FacultyMode.panelist
                    : FacultyMode.adviser),
              )
            : SegmentedButton<FacultyMode>(
                key: const Key('facultyModeSegmented'),
                segments: const [
                  ButtonSegment(
                      value: FacultyMode.adviser, label: Text('Adviser')),
                  ButtonSegment(
                      value: FacultyMode.panelist, label: Text('Panelist')),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => select(selection.first),
              ),
      ),
    );
  }
}
