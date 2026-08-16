import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class StudentDashboard extends ConsumerWidget {
  const StudentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesisAsync = ref.watch(myThesisProvider);

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('studentDashboard'),
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      // Only 'Thesis' resolves today. 'Archive' and 'Defenses' belong to
      // modules that do not exist, so they are not declared — the nav bar
      // hides itself below two destinations and returns when they land.
      destinations: const [],
      actions: const [SignOutButton()],
      body: thesisAsync.when(
        loading: () => const LoadingState(label: 'Loading your thesis…'),
        error: (_, _) => const PageShell(children: [
          ErrorState(
            message: 'Could not load your thesis group. Check your '
                'connection and try again.',
          ),
        ]),
        data: (thesis) {
          if (thesis == null) {
            return PageShell(children: [
              EmptyState(
                icon: Icons.groups_outlined,
                title: 'No thesis group yet',
                message: 'Create your group to name your working title and '
                    'list your members. You will nominate an adviser and '
                    'panel next.',
                action: FilledButton(
                  key: const Key('goToCreateThesis'),
                  onPressed: () => context.go('/thesis/create'),
                  child: const Text('Create thesis group'),
                ),
              ),
            ]);
          }

          return PageShell(
            title: thesis.workingTitle,
            subtitle: '${thesis.program} · ${thesis.semester} semester '
                '${thesis.academicYear}',
            children: [
              StatusChip(thesis.status),
              const Gap.md(),
              Text(
                StatusChip.detailFor(thesis.status),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Gap.lg(),
              FilledButton(
                key: const Key('goToThesis'),
                onPressed: () => context.go('/thesis'),
                child: const Text('Open thesis'),
              ),
              const SizedBox(height: AppTokens.sm),
            ],
          );
        },
      ),
    );
  }
}
