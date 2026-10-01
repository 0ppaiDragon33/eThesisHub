import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/defence/defence_calendar.dart';

/// The Calendar destination, at '/calendar': every dated defence the reader
/// is part of -- pre-oral, final and re-defences -- by month. The
/// Coordinator and the Dean see every defence in the college.
///
/// Its own place in the sidebar rather than a toggle on Defences, so the
/// schedule is one tap away from anywhere. Title defences have no date and
/// stay on the Defences page.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageShell(
      key: Key('calendarScreen'),
      maxWidth: AppTokens.measureWide,
      title: 'Calendar',
      subtitle: 'Scheduled pre-oral, final and re-defences.',
      children: [DefenceCalendar()],
    );
  }
}
