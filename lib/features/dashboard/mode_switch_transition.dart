import 'package:flutter/material.dart';

import 'package:ethesishub/core/widgets/success_splash.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';

/// How long the switching screen stays up before it clears itself.
const modeSwitchHold = Duration(milliseconds: 1100);

/// The heading on the switching screen: "Switching to Panelist View".
String modeSwitchTitle(FacultyMode to) =>
    'Switching to ${to == FacultyMode.adviser ? 'Adviser' : 'Panelist'} View';

/// True while a "Switching to … View" screen is up. Anything that wants to
/// open its own dialog (a celebration, say) waits for this to go false, so
/// two dialogs are never stacked on the root navigator at once.
final ValueNotifier<bool> modeSwitchShowing = ValueNotifier<bool>(false);

int _switchesShowing = 0;

/// Shows a short full-screen "Switching to … View" moment while the
/// sidebar and pages change over to the other mode, then clears itself.
/// Purely visual: the mode has already changed when this appears.
Future<void> showModeSwitchTransition(BuildContext context, FacultyMode to) {
  _switchesShowing++;
  modeSwitchShowing.value = true;
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: modeSwitchTitle(to),
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => _ModeSwitchScreen(to: to),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ).whenComplete(() {
    _switchesShowing--;
    if (_switchesShowing <= 0) {
      _switchesShowing = 0;
      modeSwitchShowing.value = false;
    }
  });
}

class _ModeSwitchScreen extends StatefulWidget {
  const _ModeSwitchScreen({required this.to});

  final FacultyMode to;

  @override
  State<_ModeSwitchScreen> createState() => _ModeSwitchScreenState();
}

class _ModeSwitchScreenState extends State<_ModeSwitchScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(modeSwitchHold, _dismiss);
  }

  /// Closes THIS screen, not whatever happens to be on top. A bare
  /// `Navigator.pop()` closes the topmost route, so if another dialog had
  /// opened over this one, that dialog closed instead and this screen
  /// stayed up for good.
  void _dismiss() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adviser = widget.to == FacultyMode.adviser;
    return SuccessSplash(
      key: const Key('modeSwitchScreen'),
      title: modeSwitchTitle(widget.to),
      subtitle: adviser
          ? 'Your menu now shows the groups you advise.'
          : 'Your menu now shows the panels you sit on.',
      status: '${adviser ? 'Adviser' : 'Panelist'} View ready',
      detail: adviser ? 'Opening your advisees…' : 'Opening your panels…',
    );
  }
}
