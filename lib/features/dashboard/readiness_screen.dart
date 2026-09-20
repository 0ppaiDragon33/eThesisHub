import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';

/// The Readiness destination on the Dean and Coordinator desks: theses whose
/// chapters have cleared the gate for a pre-oral or final defence.
class ReadinessScreen extends StatelessWidget {
  const ReadinessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageShell(
      key: Key('readinessScreen'),
      maxWidth: AppTokens.measureWide,
      title: 'Defence readiness',
      subtitle: 'Pre-oral needs Chapters I–III approved; the final defence '
          'needs all five.',
      children: [DefenceReadinessList()],
    );
  }
}
