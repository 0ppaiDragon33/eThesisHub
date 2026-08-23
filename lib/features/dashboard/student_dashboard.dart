import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/features/documents/chapters_screen.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final thesisAsync = ref.watch(myThesisProvider);
    final thesis = thesisAsync.valueOrNull;

    // Chapters is declared only once the Dean has approved a title, because
    // that is when the screen behind it stops refusing. A destination that
    // leads to "Chapters are not open yet" is the control-that-does-nothing
    // this scaffold hides its bar to avoid.
    final chaptersUnlocked =
        thesis != null && thesis.status == ThesisStatus.titleApproved;

    return ResponsiveScaffold(
      // Identifies this dashboard for routing tests. Asserting on heading
      // copy instead ties every routing test to wording that changes.
      key: const Key('studentDashboard'),
      title: 'eThesisHub',
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      // 'Archive' belongs to a module that does not exist, so it is not
      // declared — the bar hides itself below two destinations and returns
      // as they land. Chapters is the first to land, in M2.
      destinations: [
        const NavDestination(label: 'Thesis', icon: Icons.home_outlined),
        if (chaptersUnlocked)
          const NavDestination(
              label: 'Chapters', icon: Icons.menu_book_outlined),
      ],
      actions: const [SignOutButton()],
      body: (_selectedIndex == 1 && chaptersUnlocked)
          ? ChaptersScreen(thesisId: thesis.id, embedded: true)
          : thesisAsync.when(
        loading: () => const LoadingState(label: 'Loading your thesis…'),
        error: (e, _) => PageShell(children: [
          ErrorState(
            error: e,
            message: 'Could not load your thesis group.',
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
              const Gap.xl(),
              Text('My defences', style: Theme.of(context).textTheme.titleMedium),
              const Gap.sm(),
              const DefencesList(),
            ],
          );
        },
      ),
    );
  }
}
