import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
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

/// The contextual next screen for a thesis, from a staff register.
({String label, String route})? staffActionFor(Thesis t) =>
    switch (t.status) {
      ThesisStatus.nominationPendingCoordinator ||
      ThesisStatus.nominationPendingDean =>
        (label: 'Review', route: '/review'),
      ThesisStatus.titlePendingDefence =>
        (label: 'Title defence', route: '/defence/${t.id}'),
      ThesisStatus.titleApproved =>
        (label: 'Chapters', route: '/thesis/chapters?id=${t.id}'),
      ThesisStatus.archived =>
        (label: 'Record', route: '/archive/${t.id}'),
      _ => null,
    };

/// Every thesis in the college: searchable, filterable by stage, with a
/// contextual action per row. Coordinator and dean only — it watches
/// [allThesesProvider] directly.
///
/// [filter] lets a host (the pipeline bar) drive the stage filter.
class AllThesesTable extends ConsumerStatefulWidget {
  const AllThesesTable({super.key, this.filter});

  final ValueNotifier<ThesisStage?>? filter;

  @override
  ConsumerState<AllThesesTable> createState() => _AllThesesTableState();
}

class _AllThesesTableState extends ConsumerState<AllThesesTable> {
  late final ValueNotifier<ThesisStage?> _filter =
      widget.filter ?? ValueNotifier<ThesisStage?>(null);
  final _query = TextEditingController();

  @override
  void dispose() {
    if (widget.filter == null) _filter.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thesesAsync = ref.watch(allThesesProvider);

    return Panel(
      title: 'All theses',
      subtitle: 'Every group in the college',
      icon: Icons.table_rows_outlined,
      flush: true,
      child: ValueListenableBuilder<ThesisStage?>(
        valueListenable: _filter,
        builder: (context, filter, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.lg - 4, AppTokens.md, AppTokens.lg - 4, 0),
              child: Wrap(
                spacing: AppTokens.md,
                runSpacing: AppTokens.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      key: const Key('thesesSearch'),
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search title or program',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () =>
                                    setState(() => _query.clear()),
                              ),
                      ),
                    ),
                  ),
                  _FilterTabs(
                    selected: filter,
                    onSelected: (stage) => _filter.value = stage,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.md),
            // Its own loading/error/data handling: a permission error must
            // not read as "no theses in the college".
            thesesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppTokens.md),
                child: LoadingState(label: 'Loading theses…'),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppTokens.md),
                child: ErrorState(
                  error: e,
                  message: 'Could not load the thesis list.',
                ),
              ),
              data: (theses) => FadeIn(child: _Table(
                theses: theses,
                filter: filter,
                query: _query.text.trim().toLowerCase(),
              )),
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
      spacing: AppTokens.xs + 2,
      runSpacing: AppTokens.xs + 2,
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
  const _Table({
    required this.theses,
    required this.filter,
    required this.query,
  });

  final List<Thesis> theses;
  final ThesisStage? filter;
  final String query;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final t in theses)
        if ((filter == null || thesisStage(t.status) == filter) &&
            (query.isEmpty ||
                t.workingTitle.toLowerCase().contains(query) ||
                t.program.toLowerCase().contains(query)))
          t,
    ]..sort((a, b) => a.workingTitle.compareTo(b.workingTitle));

    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.lg - 4, 0, AppTokens.lg - 4, AppTokens.lg),
        child: Text(
          theses.isEmpty
              ? 'No theses on file yet.'
              : 'No theses match. Try a different stage or clear the search.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 760) {
        return Column(
          children: [for (final t in visible) _StackedRow(thesis: t)],
        );
      }
      return Column(
        children: [
          const _HeaderRow(),
          for (final t in visible) _WideRow(thesis: t),
        ],
      );
    });
  }
}

const _flexTitle = 5;
const _flexPerson = 2;
const _flexStatus = 2;
const _actionWidth = 132.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: p.muted,
        );
    return Container(
      color: p.canvas,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg - 4, vertical: AppTokens.sm + 2),
      child: Row(
        children: [
          Expanded(
              flex: _flexTitle, child: Text('Working title', style: style)),
          Expanded(flex: _flexPerson, child: Text('Leader', style: style)),
          Expanded(flex: _flexPerson, child: Text('Adviser', style: style)),
          Expanded(flex: _flexStatus, child: Text('Status', style: style)),
          const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }
}

class _WideRow extends StatelessWidget {
  const _WideRow({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final action = staffActionFor(thesis);
    return Container(
      key: ValueKey('thesisRow-${thesis.id}'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg - 4, vertical: AppTokens.md - 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _flexTitle,
            child: Padding(
              padding: const EdgeInsets.only(right: AppTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(thesis.workingTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (thesis.program.isNotEmpty)
                    Text(thesis.program,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall),
                ],
              ),
            ),
          ),
          Expanded(flex: _flexPerson, child: _NameCell(uid: thesis.leaderUid)),
          Expanded(flex: _flexPerson, child: _NameCell(uid: thesis.adviserUid)),
          Expanded(
            flex: _flexStatus,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(thesis.status, dense: true),
            ),
          ),
          SizedBox(
            width: _actionWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: action == null
                  ? const SizedBox.shrink()
                  : TextButton(
                      key: Key('thesisAction-${thesis.id}'),
                      onPressed: () => context.push(action.route),
                      child: Text(action.label),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StackedRow extends StatelessWidget {
  const _StackedRow({required this.thesis});

  final Thesis thesis;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final action = staffActionFor(thesis);
    return Container(
      key: ValueKey('thesisRow-${thesis.id}'),
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(thesis.workingTitle, style: text.titleMedium),
          const SizedBox(height: AppTokens.xs),
          StatusChip(thesis.status, dense: true),
          const SizedBox(height: AppTokens.sm),
          Row(
            children: [
              Text('Leader ', style: text.bodySmall),
              Expanded(child: _NameCell(uid: thesis.leaderUid)),
            ],
          ),
          Row(
            children: [
              Text('Adviser ', style: text.bodySmall),
              Expanded(child: _NameCell(uid: thesis.adviserUid)),
            ],
          ),
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push(action.route),
                child: Text(action.label),
              ),
            ),
        ],
      ),
    );
  }
}

/// One name cell, its own widget so its loading state does not stall the
/// whole register.
class _NameCell extends ConsumerWidget {
  const _NameCell({required this.uid});

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(_userNameProvider(uid));
    final style = Theme.of(context).textTheme.bodyMedium;
    return nameAsync.when(
      loading: () => const Align(
        alignment: Alignment.centerLeft,
        child: Shimmer(child: SkeletonBox(width: 90)),
      ),
      error: (_, _) => Text('Unavailable', style: style),
      data: (name) => Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
