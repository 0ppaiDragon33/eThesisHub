import 'package:flutter/material.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/dashboard/defence_queue.dart';

/// The Titles destination on the Dean and Coordinator dashboards: groups
/// presenting their candidate titles.
class TitleDefencesScreen extends StatelessWidget {
  const TitleDefencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageShell(
      key: Key('titleDefencesScreen'),
      title: 'Title defences',
      subtitle: 'Groups presenting their candidate titles.',
      children: [DefenceQueue()],
    );
  }
}
