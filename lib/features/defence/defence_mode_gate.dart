import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/features/dashboard/mode_switch_transition.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';

/// The faculty mode a defence demands of this reader, or `null` when the
/// defence does not tie them to one.
///
/// The adviser's chair is checked first: an adviser is never in `panelUids`
/// (they cannot score their own group), but checking in this order keeps the
/// answer unambiguous if data ever says otherwise.
FacultyMode? defenceModeNeeded(Defence defence, String? uid) {
  if (uid == null) return null;
  if (uid == defence.adviserUid) return FacultyMode.adviser;
  if (defence.panelUids.contains(uid)) return FacultyMode.panelist;
  return null;
}

enum DefenceModeGate { allow, loading, blocked }

class DefenceModeGateResult {
  const DefenceModeGateResult(this.gate, this.needed);

  final DefenceModeGate gate;

  /// The mode the reader must be in; only meaningful when [gate] is not
  /// [DefenceModeGate.allow].
  final FacultyMode? needed;
}

/// Decides whether the reader may be inside this defence in the mode they
/// are currently in.
///
/// A member who holds BOTH capabilities may be adviser of one group and a
/// panelist on another thesis' panel; the Adviser/Panelist switch exists to
/// keep those two jobs apart. The room, the manuscript, the evaluation and
/// the grades all belong to ONE of those jobs for a given defence, so
/// standing in the other mode keeps them out until they switch.
///
/// Members with a single capability have no other mode to be in and are
/// never blocked. Readers with no position on this defence (the group, the
/// Coordinator, the Dean) are not governed by the switch at all.
///
/// While the mode is still resolving this returns [DefenceModeGate.loading]
/// rather than allowing, so nothing from the room flashes up before the
/// check lands. If the mode cannot be resolved (a failed read), it allows:
/// this is a UX boundary, the Firestore rules remain the security one.
DefenceModeGateResult checkDefenceModeGate(
  WidgetRef ref,
  Defence defence,
  String? uid,
) {
  final needed = defenceModeNeeded(defence, uid);
  if (needed == null) {
    return const DefenceModeGateResult(DefenceModeGate.allow, null);
  }

  final modeAsync = ref.watch(effectiveFacultyModeProvider);
  final bothAsync = ref.watch(facultyHoldsBothCapabilitiesProvider);
  if (modeAsync.isLoading || bothAsync.isLoading) {
    return DefenceModeGateResult(DefenceModeGate.loading, needed);
  }

  final mode = modeAsync.valueOrNull;
  final bothCapable = bothAsync.valueOrNull ?? false;
  if (mode == null || !bothCapable || mode == needed) {
    return DefenceModeGateResult(DefenceModeGate.allow, needed);
  }
  return DefenceModeGateResult(DefenceModeGate.blocked, needed);
}

/// What a blocked reader sees instead of the defence: why, and a button
/// that switches mode so they can walk straight in.
class DefenceModeBlock extends ConsumerWidget {
  const DefenceModeBlock({super.key, required this.needed});

  final FacultyMode needed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdviser = needed == FacultyMode.adviser;
    return EmptyState(
      key: const Key('defenceModeBlock'),
      icon: Icons.swap_horiz_rounded,
      title: 'Switch to ${needed.label} mode',
      message: isAdviser
          ? 'You are the adviser for this defense. Open it in Adviser mode.'
          : 'You are on the panel for this defense. Open it in Panelist mode.',
      action: FilledButton(
        key: const Key('defenceModeBlockButton'),
        onPressed: () {
          ref.read(facultyModeProvider.notifier).set(needed);
          showModeSwitchTransition(context, needed);
        },
        child: Text('Switch to ${needed.label}'),
      ),
    );
  }
}
