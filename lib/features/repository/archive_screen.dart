import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/providers/archive_providers.dart';

/// The college-wide browse of every approved thesis.
///
/// The one screen in the app not scoped to what the reader is personally
/// involved in: [archiveProvider] holds every published thesis, and this
/// screen just searches and filters it client-side (D54 — Firestore has no
/// substring search, so the filtering has to happen here rather than in
/// the query).
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  String _query = '';
  String? _college;
  String? _program;
  String? _year;

  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('archive'),
        child: PageShell(
          title: 'Thesis Archive',
          subtitle: 'Every approved thesis, across every college.',
          children: children,
        ),
      );

  /// The distinct values of [selector] across every loaded entry, in the
  /// order they first appear — stable across rebuilds rather than
  /// alphabetised, so the chip row does not reshuffle as someone filters.
  List<String> _distinct(
    List<ArchiveEntry> entries,
    String Function(ArchiveEntry) selector,
  ) {
    final seen = <String>{};
    final out = <String>[];
    for (final e in entries) {
      final v = selector(e);
      if (v.isNotEmpty && seen.add(v)) out.add(v);
    }
    return out;
  }

  Widget _filterRow(
    String prefix,
    List<String> values,
    String? selected,
    ValueChanged<String?> onSelect,
  ) {
    return Wrap(
      spacing: AppTokens.sm,
      runSpacing: AppTokens.sm,
      children: [
        for (final v in values)
          FilterChip(
            key: Key('filter-$prefix-$v'),
            label: Text(v),
            selected: selected == v,
            onSelected: (nowSelected) =>
                onSelect(nowSelected ? v : null),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final archiveAsync = ref.watch(archiveProvider);

    if (archiveAsync.isLoading) {
      return _framed(const [
        LoadingState(key: Key('archiveLoading'), label: 'Loading the archive…'),
      ]);
    }
    if (archiveAsync.hasError) {
      return _framed([
        ErrorState(
          error: archiveAsync.error,
          message: 'Could not load the archive.',
        ),
      ]);
    }

    final entries = archiveAsync.valueOrNull ?? const <ArchiveEntry>[];

    if (entries.isEmpty) {
      return _framed(const [
        EmptyState(
          key: Key('emptyArchive'),
          icon: Icons.inbox_outlined,
          title: 'No theses have been archived yet.',
          message: 'Approved theses appear here once the Coordinator '
              'archives them.',
        ),
      ]);
    }

    final colleges = _distinct(entries, (e) => e.college);
    final programs = _distinct(entries, (e) => e.program);
    final years = _distinct(entries, (e) => e.academicYear);

    // A selected value can vanish from the live stream out from under the
    // reader -- most concretely, the Coordinator retracting the one
    // archive entry left in a college the reader has filtered on
    // (ArchiveRepository.retract). Left alone, the chip disappears from
    // the Wrap below while the field still holds the value, so the list
    // renders `noMatches` with no visible chip left to clear it: a dead
    // end reachable only by leaving the screen. Pruned here instead, a
    // plain field mutation rather than setState -- safe during build, and
    // it makes this build's `filtered` and the next build's chip row
    // agree, so nothing needs its own recovery affordance.
    if (_college != null && !colleges.contains(_college)) _college = null;
    if (_program != null && !programs.contains(_program)) _program = null;
    if (_year != null && !years.contains(_year)) _year = null;

    final filtered = entries
        .where((e) => e.matches(_query))
        .where((e) => _college == null || e.college == _college)
        .where((e) => _program == null || e.program == _program)
        .where((e) => _year == null || e.academicYear == _year)
        .toList();

    return _framed([
      TextField(
        key: const Key('archiveSearch'),
        decoration: const InputDecoration(
          labelText: 'Search',
          hintText: 'Search by title or author',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
      const Gap.md(),
      _filterRow('college', colleges, _college,
          (v) => setState(() => _college = v)),
      const Gap.sm(),
      _filterRow('program', programs, _program,
          (v) => setState(() => _program = v)),
      const Gap.sm(),
      _filterRow('year', years, _year, (v) => setState(() => _year = v)),
      const Gap.lg(),
      if (filtered.isEmpty)
        const EmptyState(
          key: Key('noMatches'),
          icon: Icons.search_off,
          title: 'No theses match that search.',
          message: 'Try a different search term or clear a filter.',
        )
      else
        for (final e in filtered) _ArchiveCard(entry: e),
    ]);
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.entry});

  final ArchiveEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // An entry with no members recorded still needs a line here rather
    // than a blank one -- "Unknown authors" says plainly that the field is
    // empty, not that the card failed to render.
    final authors =
        entry.authorsLabel.isNotEmpty ? entry.authorsLabel : 'Unknown authors';

    return Card(
      key: Key('archiveCard-${entry.thesisId}'),
      margin: const EdgeInsets.only(bottom: AppTokens.sm),
      child: InkWell(
        onTap: () => context.push('/archive/${entry.thesisId}'),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title, style: text.titleMedium),
              const SizedBox(height: AppTokens.xs),
              Text(authors, style: text.bodyMedium?.copyWith(color: muted)),
              const SizedBox(height: AppTokens.xs),
              Text(
                '${entry.program} · ${entry.academicYear}',
                style: text.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: AppTokens.sm),
              Text(
                entry.abstract,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
