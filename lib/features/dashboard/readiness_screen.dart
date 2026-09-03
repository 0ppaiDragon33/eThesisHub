import 'package:flutter/material.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';

/// The Readiness destination on the Dean and Coordinator dashboards:
/// theses whose chapters have cleared the gate for a pre-oral or final
/// defence.
class ReadinessScreen extends StatelessWidget {
  const ReadinessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageShell(
      key: Key('readinessScreen'),
      title: 'Defence readiness',
      subtitle: 'Theses whose chapters have cleared the gate for a '
          'pre-oral or final defence.',
      children: [DefenceReadinessList()],
    );
  }
}
