import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/dashboard/defence_queue.dart';

/// The Title defences destination on the Dean and Coordinator desks.
class TitleDefencesScreen extends StatelessWidget {
  const TitleDefencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageShell(
      key: Key('titleDefencesScreen'),
      maxWidth: AppTokens.measureWide,
      title: 'Title defences',
      subtitle: 'Groups presenting their candidate titles. Panel members '
          'comment; the Dean records the approved title or returns the set.',
      children: [DefenceQueue()],
    );
  }
}
