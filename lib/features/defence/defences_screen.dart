import 'package:flutter/material.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/defence/defences_list.dart';

/// The Defences destination, at '/defences': a [PageShell] wrapping
/// [DefencesList].
///
/// The heading used to be tailored per role, because each of the four
/// dashboards hosted this body itself and passed its own wording in. Those
/// dashboards are gone and '/defences' is one route reached by one
/// sidebar entry, so it carries one heading. [DefencesList] itself is
/// already per-reader — it shows the defences you are actually party to —
/// which is where the difference between a student's view and a
/// panelist's actually lives.
///
/// [title] and [subtitle] stay overridable for a caller that embeds this
/// list under a different heading.
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
