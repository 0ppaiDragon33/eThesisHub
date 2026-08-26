import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// A name for a uid, resolved from `users/{uid}` -- the same document
/// `thesis_status_screen.dart`'s Form 1 download resolves a leader's name
/// from, and the same one `student_overview.dart` resolves an adviser's
/// name from (there, via the faculty directory; here, via the profile
/// itself, since a leader is a student and never appears in that
/// directory). One read per uid, cached by Riverpod for the life of the
/// table rather than repeated per rebuild.
final _userNameProvider = FutureProvider.family<String, String?>((ref, uid) async {
  if (uid == null || uid.isEmpty) return 'Not yet assigned';
  final user = await ref.watch(userRepositoryProvider).fetchUser(uid);
  return user?.fullName ?? 'Unknown';
});

/// Every thesis in the college, filterable by stage, for the coordinator and
/// dean dashboards -- it watches [allThesesProvider] directly, which the
/// security rules permit only for those two roles.
///
/// No Score column: a score belongs to a milestone this task does not
/// build.
class AllThesesTable extends ConsumerStatefulWidget {
  const AllThesesTable({super.key});

  @override
  ConsumerState<AllThesesTable> createState() => _AllThesesTableState();
}

class _AllThesesTableState extends ConsumerState<AllThesesTable> {
  /// `null` means "All". Otherwise one of [ThesisStage.values] -- the exact
  /// buckets `StageDonut` groups its own counts into, via the shared
  /// `thesisStage()` helper, so the table and the donut can never disagree
  /// about what "Nomination" or "Chapters" means.
  ThesisStage? _filter;

  @override
  Widget build(BuildContext context) {
    final thesesAsync = ref.watch(allThesesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All theses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.md),
            _FilterTabs(
              selected: _filter,
              onSelected: (stage) => setState(() => _filter = stage),
            ),
            const SizedBox(height: AppTokens.md),
            // Its own loading/error/data handling, never `valueOrNull ??
            // []`: a permission error or a slow first snapshot must not
            // read the same as "no theses in the college".
            thesesAsync.when(
              loading: () => const LoadingState(label: 'Loading theses…'),
              error: (e, _) => ErrorState(
                error: e,
                message: 'Could not load the thesis list.',
              ),
              data: (theses) => _Table(theses: theses, filter: _filter),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.selected, required this.onSelected});

  final ThesisStage? selected;
  final ValueChanged<ThesisStage?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTokens.sm,
      runSpacing: AppTokens.sm,
      children: [
        ChoiceChip(
          key: const Key('thesesFilter-all'),
          label: const Text('All'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final stage in ThesisStage.values)
          ChoiceChip(
            key: Key('thesesFilter-${stage.name}'),
            label: Text(stage.label),
            selected: selected == stage,
            onSelected: (_) => onSelected(stage),
          ),
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.theses, required this.filter});

  final List<Thesis> theses;
  final ThesisStage? filter;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final t in theses)
        if (filter == null || thesisStage(t.status) == filter) t,
      // Sorted by working title, not left in whatever order the stream
      // handed them back -- `fake_cloud_firestore` (and Firestore itself,
      // absent an explicit orderBy) returns documents in insertion order,
      // which is not the order a reader scanning a table expects.
    ]..sort((a, b) => a.workingTitle.compareTo(b.workingTitle));

    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'No theses match this filter',
        message: 'Try a different stage, or clear the filter.',
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Working title')),
          DataColumn(label: Text('Leader')),
          DataColumn(label: Text('Adviser')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final t in visible)
            DataRow(
              key: ValueKey('thesisRow-${t.id}'),
              cells: [
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(t.workingTitle, overflow: TextOverflow.ellipsis),
                )),
                DataCell(_NameCell(uid: t.leaderUid)),
                DataCell(_NameCell(uid: t.adviserUid)),
                DataCell(StatusChip(t.status, dense: true)),
              ],
            ),
        ],
      ),
    );
  }
}

/// One name cell, its own [ConsumerWidget] so its own loading state does
/// not stall the whole table -- the same reasoning `_ReadinessRow` in
/// `defence_readiness.dart` gives for splitting its per-thesis chapter
/// watch into its own widget.
class _NameCell extends ConsumerWidget {
  const _NameCell({required this.uid});

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(_userNameProvider(uid));
    return nameAsync.when(
      loading: () => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => const Text('—'),
      data: (name) => Text(name),
    );
  }
}
