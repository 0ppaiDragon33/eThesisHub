import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/features/dashboard/mode_switch_transition.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';

/// A one-line notice, with a button, for a faculty member on a screen that
/// belongs to the OTHER mode.
///
/// Renders nothing unless the member holds BOTH capabilities and the mode in
/// force differs from [needed]. A member with a single capability has no
/// other mode to move to, so a button for it would do nothing: the same
/// reason the Adviser/Panelist switch in the shell hides for them.
class SwitchModeNotice extends ConsumerWidget {
  const SwitchModeNotice({
    super.key,
    required this.needed,
    required this.message,
  });

  /// The mode this screen belongs to.
  final FacultyMode needed;

  /// One short line saying why to switch.
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(effectiveFacultyModeProvider).valueOrNull;
    final bothCapable =
        ref.watch(facultyHoldsBothCapabilitiesProvider).valueOrNull ?? false;
    if (mode == null || !bothCapable || mode == needed) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.md),
      child: Panel(
        key: const Key('switchModeNotice'),
        emphasis: true,
        child: Row(
          children: [
            Expanded(
              child: Text(message,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            const SizedBox(width: AppTokens.md),
            FilledButton(
              key: const Key('switchModeNoticeButton'),
              onPressed: () {
                ref.read(facultyModeProvider.notifier).set(needed);
                showModeSwitchTransition(context, needed);
              },
              child: Text('Switch to ${needed.label}'),
            ),
          ],
        ),
      ),
    );
  }
}
