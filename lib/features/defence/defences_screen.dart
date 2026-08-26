import 'package:flutter/material.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/defence/defences_list.dart';

/// The Defences destination on every dashboard: a [PageShell] wrapping
/// [DefencesList]. The heading copy is tailored per role -- a student
/// reads about their own comments, faculty about whichever positions they
/// hold -- so each dashboard supplies its own [title] and [subtitle]
/// exactly as it did before this screen was pulled out on its own; the
/// Dean and Coordinator share the same wording, which is why it is also
/// this widget's default.
class DefencesScreen extends StatelessWidget {
  const DefencesScreen({
    super.key,
    this.title = 'Scheduled defences',
    this.subtitle = 'Pre-oral and final defences, and the rooms they run '
        'in.',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      key: const Key('defencesScreen'),
      title: title,
      subtitle: subtitle,
      children: const [DefencesList()],
    );
  }
}
