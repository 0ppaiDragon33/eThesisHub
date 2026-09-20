import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
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
          maxWidth: AppTokens.measureWide,
          kicker: 'College archive',
          title: 'Thesis archive',
          subtitle: 'Every published thesis, across every college. Search '
              'by title or author, or narrow by college, program and year.',
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
      spacing: AppTokens.xs + 2,
      runSpacing: AppTokens.xs + 2,
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

    final activeFilters =
        [_college, _program, _year].where((v) => v != null).length;

    final search = TextField(
      key: const Key('archiveSearch'),
      decoration: const InputDecoration(
        hintText: 'Search by title or author',
        prefixIcon: Icon(Icons.search_rounded),
      ),
      onChanged: (v) => setState(() => _query = v),
    );

    Widget facet(String label, Widget chips) => Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: AppTokens.sm),
              chips,
            ],
          ),
        );

    final filters = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        facet('College', _filterRow('college', colleges, _college,
            (v) => setState(() => _college = v))),
        facet('Program', _filterRow('program', programs, _program,
            (v) => setState(() => _program = v))),
        facet('Academic year', _filterRow('year', years, _year,
            (v) => setState(() => _year = v))),
        if (activeFilters > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('clearArchiveFilters'),
              onPressed: () => setState(() {
                _college = null;
                _program = null;
                _year = null;
              }),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear filters'),
            ),
          ),
      ],
    );

    final results = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.sm + 2),
          child: Text(
            filtered.length == 1
                ? '1 thesis'
                : '${filtered.length} theses',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        if (filtered.isEmpty)
          const EmptyState(
            key: Key('noMatches'),
            icon: Icons.search_off,
            title: 'No theses match that search.',
            message: 'Try a different search term or clear a filter.',
          )
        else
          for (final (i, e) in filtered.indexed)
            FadeIn(
              key: ValueKey('fade-${e.thesisId}'),
              delay: Duration(milliseconds: 30 * (i < 8 ? i : 8)),
              child: _ArchiveCard(entry: e),
            ),
      ],
    );

    return _framed([
      search,
      const Gap.lg(),
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                flush: true,
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: AppTokens.md),
                  childrenPadding: const EdgeInsets.fromLTRB(
                      AppTokens.md, 0, AppTokens.md, AppTokens.sm),
                  title: Text(activeFilters == 0
                      ? 'Filters'
                      : 'Filters ($activeFilters on)'),
                  children: [filters],
                ),
              ),
              const Gap.md(),
              results,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 260,
              child: Panel(title: 'Filters', child: filters),
            ),
            const SizedBox(width: AppTokens.lg),
            Expanded(child: results),
          ],
        );
      }),
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

    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm + 4),
      child: Material(
        key: Key('archiveCard-${entry.thesisId}'),
        color: p.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          side: BorderSide(color: p.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/archive/${entry.thesisId}'),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The spine: the year the thesis belongs to.
                Container(
                  width: 72,
                  color: p.seal.withValues(alpha: 0.07),
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
                  child: Column(
                    children: [
                      Icon(Icons.menu_book_outlined, color: p.seal, size: 22),
                      const SizedBox(height: AppTokens.sm),
                      Text(
                        entry.academicYear.replaceAll('-', '–\n'),
                        textAlign: TextAlign.center,
                        style: text.labelSmall?.copyWith(color: p.seal),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.md + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title, style: text.titleLarge),
                        const SizedBox(height: AppTokens.xs),
                        Text(authors,
                            style: text.bodyMedium?.copyWith(color: muted)),
                        const SizedBox(height: AppTokens.sm),
                        Text(
                          entry.abstract,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: AppTokens.sm),
                        Text(
                          [entry.college, entry.program]
                              .where((x) => x.isNotEmpty)
                              .join(', '),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
