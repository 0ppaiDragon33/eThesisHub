import 'dart:async';

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
import 'package:ethesishub/providers/auth_providers.dart';

/// The three ways the archive can be narrowed down.
enum _Facet {
  college('college', 'College', Icons.account_balance_outlined),
  program('program', 'Program', Icons.school_outlined),
  year('year', 'Academic year', Icons.calendar_today_outlined);

  const _Facet(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

enum _Sort {
  newest('Newest first'),
  oldest('Oldest first'),
  title('Title A–Z'),
  author('Author A–Z');

  const _Sort(this.label);
  final String label;
}

enum _Layout { list, grid }

/// The college-wide browse of every approved thesis.
///
/// The one screen in the app not scoped to what the reader is personally
/// involved in: [archiveProvider] holds every published thesis, and this
/// screen searches, filters and sorts it client-side (Firestore has
/// no substring search, so the filtering has to happen here rather than in
/// the query).
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  String _query = '';
  final Map<_Facet, String?> _selected = {};
  _Sort _sort = _Sort.newest;
  _Layout _layout = _Layout.list;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Widget _framed(List<Widget> children) => KeyedSubtree(
    key: const Key('archive'),
    child: PageShell(
      maxWidth: AppTokens.measureWide,
      kicker: 'College archive',
      title: 'Thesis archive',
      subtitle: (ref.watch(currentUserProvider).valueOrNull?.isFaculty ?? true)
          ? 'Every published thesis.'
          : 'Your published thesis.',
      children: children,
    ),
  );

  String _value(_Facet f, ArchiveEntry e) => switch (f) {
    _Facet.college => e.college,
    _Facet.program => e.program,
    _Facet.year => e.academicYear,
  };

  /// The distinct values of [selector] across every loaded entry, in the
  /// order they first appear: stable across rebuilds rather than
  /// alphabetised, so the menu does not reshuffle as someone filters.
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

  /// Whether [e] passes the search and every active facet, optionally
  /// ignoring one facet ([skip]) so its menu can show how many results each
  /// of its options would give.
  bool _passes(ArchiveEntry e, {_Facet? skip}) {
    if (!e.matches(_query)) return false;
    for (final f in _Facet.values) {
      if (f == skip) continue;
      final sel = _selected[f];
      if (sel != null && _value(f, e) != sel) return false;
    }
    return true;
  }

  int _compare(ArchiveEntry a, ArchiveEntry b) {
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    final primary = switch (_sort) {
      _Sort.newest => b.academicYear.compareTo(a.academicYear),
      _Sort.oldest => a.academicYear.compareTo(b.academicYear),
      _Sort.title => byTitle,
      _Sort.author => a.authorsLabel.toLowerCase().compareTo(
        b.authorsLabel.toLowerCase(),
      ),
    };
    return primary != 0 ? primary : byTitle;
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _query = v);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtl.clear();
    setState(() => _query = '');
  }

  void _clearFilters() => setState(_selected.clear);

  Widget _facetMenu(_Facet f, List<ArchiveEntry> entries) {
    final values = _distinct(entries, (e) => _value(f, e));
    final counts = <String, int>{};
    for (final e in entries.where((e) => _passes(e, skip: f))) {
      final v = _value(f, e);
      if (v.isNotEmpty) counts.update(v, (n) => n + 1, ifAbsent: () => 1);
    }
    final selected = _selected[f];

    return PopupMenuButton<String>(
      key: Key('facet-${f.id}'),
      tooltip: 'Filter by ${f.label.toLowerCase()}',
      position: PopupMenuPosition.under,
      onSelected: (v) =>
          setState(() => _selected[f] = v == selected ? null : v),
      itemBuilder: (_) => [
        for (final v in values)
          CheckedPopupMenuItem<String>(
            key: Key('filter-${f.id}-$v'),
            value: v,
            checked: v == selected,
            // An option that would return nothing is shown but not
            // pickable, unless it is the one already selected.
            enabled: v == selected || (counts[v] ?? 0) > 0,
            child: Text('$v  (${counts[v] ?? 0})'),
          ),
      ],
      child: _MenuFace(
        icon: f.icon,
        label: selected ?? f.label,
        active: selected != null,
      ),
    );
  }

  Widget _sortMenu() => PopupMenuButton<_Sort>(
    key: const Key('archiveSort'),
    tooltip: 'Sort theses',
    position: PopupMenuPosition.under,
    onSelected: (s) => setState(() => _sort = s),
    itemBuilder: (_) => [
      for (final s in _Sort.values)
        CheckedPopupMenuItem<_Sort>(
          value: s,
          checked: s == _sort,
          child: Text(s.label),
        ),
    ],
    child: _MenuFace(icon: Icons.sort_rounded, label: _sort.label),
  );

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
          message:
              'Approved theses appear here once the Coordinator '
              'archives them.',
        ),
      ]);
    }

    // A selected value can vanish from the live stream out from under the
    // reader: most concretely, the Coordinator retracting the one
    // archive entry left in a college the reader has filtered on
    // (ArchiveRepository.retract). Left alone, the filter would keep
    // hiding everything with nothing visible to clear. Pruned here, a
    // plain field mutation rather than setState: safe during build.
    for (final f in _Facet.values) {
      final sel = _selected[f];
      if (sel != null &&
          !_distinct(entries, (e) => _value(f, e)).contains(sel)) {
        _selected[f] = null;
      }
    }

    final filtered = entries.where((e) => _passes(e)).toList()..sort(_compare);

    final activeFacets = [
      for (final f in _Facet.values)
        if (_selected[f] != null) f,
    ];

    final search = TextField(
      key: const Key('archiveSearch'),
      controller: _searchCtl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by title or author',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchCtl,
          builder: (_, v, _) => v.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  key: const Key('clearArchiveSearch'),
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _clearSearch,
                ),
        ),
      ),
      onChanged: _onSearchChanged,
    );

    final gap = AppTokens.sm + 2;

    final facetMenus = [for (final f in _Facet.values) _facetMenu(f, entries)];

    final layoutToggle = SegmentedButton<_Layout>(
      key: const Key('archiveLayout'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: _Layout.list,
          icon: Icon(Icons.view_agenda_outlined),
          tooltip: 'List view',
        ),
        ButtonSegment(
          value: _Layout.grid,
          icon: Icon(Icons.grid_view_rounded),
          tooltip: 'Grid view',
        ),
      ],
      selected: {_layout},
      onSelectionChanged: (s) => setState(() => _layout = s.first),
    );

    // One compact toolbar instead of a tall filter panel: facets on the
    // left, sort and layout on the right, wrapping on narrow screens.
    final toolbar = LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 860) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [...facetMenus, _sortMenu()],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Wrap(spacing: gap, runSpacing: gap, children: facetMenus),
            ),
            SizedBox(width: AppTokens.md),
            _sortMenu(),
            SizedBox(width: gap),
            layoutToggle,
          ],
        );
      },
    );

    // What is currently filtering the list, each removable on its own.
    final activeRow = activeFacets.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.only(top: gap),
            child: Wrap(
              spacing: gap,
              runSpacing: gap / 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final f in activeFacets)
                  InputChip(
                    key: Key('active-${f.id}'),
                    label: Text('${f.label}: ${_selected[f]}'),
                    onDeleted: () => setState(() => _selected[f] = null),
                  ),
                TextButton.icon(
                  key: const Key('clearArchiveFilters'),
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear filters'),
                ),
              ],
            ),
          );

    final narrowing = _query.isNotEmpty || activeFacets.isNotEmpty;
    final countLabel = narrowing
        ? '${filtered.length} of ${entries.length} '
              '${entries.length == 1 ? 'thesis' : 'theses'}'
        : (filtered.length == 1 ? '1 thesis' : '${filtered.length} theses');

    final results = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: AppTokens.sm + 2),
          child: Text(
            countLabel,
            key: const Key('archiveCount'),
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
          LayoutBuilder(
            builder: (context, c) {
              final cols = _layout == _Layout.grid
                  ? (c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 700 ? 2 : 1))
                  : 1;

              if (cols == 1) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, e) in filtered.indexed)
                      FadeIn(
                        key: ValueKey('fade-${e.thesisId}'),
                        delay: Duration(milliseconds: 30 * (i < 8 ? i : 8)),
                        child: _ArchiveCard(entry: e),
                      ),
                  ],
                );
              }

              final spacing = AppTokens.sm + 4;
              final w = (c.maxWidth - spacing * (cols - 1)) / cols;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final (i, e) in filtered.indexed)
                    SizedBox(
                      width: w,
                      child: FadeIn(
                        key: ValueKey('fade-${e.thesisId}'),
                        delay: Duration(milliseconds: 30 * (i < 8 ? i : 8)),
                        child: _ArchiveTile(entry: e),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );

    return _framed([
      search,
      const Gap.md(),
      toolbar,
      if (activeRow != null) activeRow,
      const Gap.lg(),
      results,
    ]);
  }
}

/// The face of a menu button: an outlined pill that fills with the accent
/// colour once it is holding a choice.
class _MenuFace extends StatelessWidget {
  const _MenuFace({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: active ? p.seal : null,
      fontWeight: active ? FontWeight.w600 : null,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.xs + 2,
      ),
      decoration: BoxDecoration(
        color: active ? p.seal.withValues(alpha: 0.08) : p.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? p.seal : p.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: active ? p.seal : null),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis, style: style),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 20, color: active ? p.seal : null),
        ],
      ),
    );
  }
}

/// A small outlined label for the college and program of a thesis.
class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.rule),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Shared pieces of the two card layouts, so the list row and the grid tile
/// never drift apart.
mixin _CardParts {
  String authorsOf(ArchiveEntry entry) =>
      // An entry with no members recorded still needs a line here rather
      // than a blank one: "Unknown authors" says plainly that the field
      // is empty, not that the card failed to render.
      entry.authorsLabel.isNotEmpty ? entry.authorsLabel : 'Unknown authors';

  Widget tags(ArchiveEntry entry) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final t in [entry.college, entry.program])
        if (t.isNotEmpty) _Tag(t),
    ],
  );

  Widget abstractOf(BuildContext context, ArchiveEntry entry, int lines) {
    if (entry.abstract.trim().isEmpty) {
      return Text(
        'No abstract provided.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Text(
      entry.abstract,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

/// List layout: a spine carrying the academic year, then the thesis.
class _ArchiveCard extends StatelessWidget with _CardParts {
  const _ArchiveCard({required this.entry});

  final ArchiveEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = Palette.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: AppTokens.sm + 4),
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
                  padding: EdgeInsets.symmetric(vertical: AppTokens.md),
                  child: Column(
                    children: [
                      Icon(Icons.menu_book_outlined, color: p.seal, size: 22),
                      SizedBox(height: AppTokens.sm),
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
                    padding: EdgeInsets.all(AppTokens.md + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title, style: text.titleLarge),
                        SizedBox(height: AppTokens.xs),
                        Row(
                          children: [
                            Icon(Icons.people_outline, size: 16, color: muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                authorsOf(entry),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(color: muted),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: AppTokens.sm),
                        abstractOf(context, entry, 2),
                        SizedBox(height: AppTokens.sm + 2),
                        tags(entry),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(right: AppTokens.sm),
                  child: Icon(Icons.chevron_right_rounded, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grid layout: the same information stacked, for scanning many theses at
/// once on a wide screen.
class _ArchiveTile extends StatelessWidget with _CardParts {
  const _ArchiveTile({required this.entry});

  final ArchiveEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = Palette.of(context);

    return Material(
      key: Key('archiveCard-${entry.thesisId}'),
      color: p.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: BorderSide(color: p.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/archive/${entry.thesisId}'),
        child: Padding(
          padding: EdgeInsets.all(AppTokens.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: p.seal, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    entry.academicYear,
                    style: text.labelMedium?.copyWith(color: p.seal),
                  ),
                ],
              ),
              SizedBox(height: AppTokens.sm),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge,
              ),
              SizedBox(height: AppTokens.xs),
              Text(
                authorsOf(entry),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: muted),
              ),
              SizedBox(height: AppTokens.sm),
              abstractOf(context, entry, 3),
              SizedBox(height: AppTokens.sm + 2),
              tags(entry),
            ],
          ),
        ),
      ),
    );
  }
}
