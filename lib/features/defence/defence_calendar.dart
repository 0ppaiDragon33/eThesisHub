import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defence_status.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// A month grid of the same defences [DefencesList] shows, reading the
/// same [myDefencesProvider] so the two presentations cannot disagree.
///
/// Hand-rolled -- no calendar package. The whole layout algorithm is: the
/// Monday on or before the 1st, plus six weeks, giving a fixed 42-cell
/// grid that never reshapes as the month's day count changes.
class DefenceCalendar extends ConsumerStatefulWidget {
  const DefenceCalendar({super.key, this.where});

  /// Which of the reader's defences to show; all of them when null.
  final bool Function(Defence)? where;

  @override
  ConsumerState<DefenceCalendar> createState() => _DefenceCalendarState();
}

class _DefenceCalendarState extends ConsumerState<DefenceCalendar> {
  late DateTime _month;
  late DateTime _selected;

  static const _weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ];

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _month = DateTime(today.year, today.month, 1);
    _selected = today;
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  void _select(DateTime day) {
    setState(() => _selected = day);
  }

  static String _cellKey(DateTime day) =>
      'calendarCell-${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final defencesAsync = ref.watch(myDefencesProvider);

    // Loading/error/empty stay apart, exactly like DefencesList: a month
    // that could not load must not read as a month with nothing in it.
    return defencesAsync.when(
      loading: () => const LoadingState(label: 'Loading your defences…'),
      error: (e, _) => ErrorState(
        error: e,
        message: 'Could not load your defences.',
      ),
      data: (defences) {
        final shown =
            widget.where == null ? defences : defences.where(widget.where!).toList();
        if (shown.isEmpty) {
          return const EmptyState(
            key: Key('noDefences'),
            icon: Icons.forum_outlined,
            title: 'No defences scheduled',
            message: 'A defence appears here once the Coordinator schedules '
                'one you are part of.',
          );
        }
        return _buildCalendar(context, shown);
      },
    );
  }

  Widget _buildCalendar(BuildContext context, List<Defence> defences) {
    final brightness = Theme.of(context).brightness;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    // A defence with no confirmed date belongs on no day -- it is never
    // bucketed by [DateUtils.dateOnly] below, so it can neither land on
    // the epoch nor silently vanish; it is listed separately instead.
    final awaiting = defences.where((d) => d.scheduledAt == null).toList();

    final byDay = <DateTime, List<Defence>>{};
    for (final d in defences) {
      final at = d.scheduledAt;
      if (at == null) continue;
      byDay.putIfAbsent(DateUtils.dateOnly(at), () => []).add(d);
    }

    final first = DateTime(_month.year, _month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final days = List.generate(42, (i) => start.add(Duration(days: i)));
    final today = DateUtils.dateOnly(DateTime.now());

    final selectedDefences = [...(byDay[_selected] ?? const <Defence>[])]
      ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));

    final grid = Panel(
      flush: true,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_monthNames[_month.month - 1]} ${_month.year}',
                    style: text.headlineSmall,
                  ),
                ),
                IconButton(
                  key: const Key('calendarPrevMonth'),
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _changeMonth(-1),
                ),
                IconButton(
                  key: const Key('calendarNextMonth'),
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.sm),
            Row(
              children: [
                for (final label in _weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(label,
                          style: text.labelSmall?.copyWith(color: muted)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.xs),
            for (var w = 0; w < 6; w++)
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: _DayCell(
                        day: days[w * 7 + i],
                        inMonth: days[w * 7 + i].month == _month.month,
                        isToday: days[w * 7 + i] == today,
                        isSelected: days[w * 7 + i] == _selected,
                        defences: byDay[days[w * 7 + i]] ?? const [],
                        brightness: brightness,
                        onTap: () => _select(days[w * 7 + i]),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: AppTokens.md),
            _Legend(brightness: brightness),
          ],
        ),
      ),
    );

    final dayPanel = Panel(
      key: const Key('calendarDayPanel'),
      title: _dayPanelHeading(_selected, today),
      icon: Icons.today_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selectedDefences.isEmpty)
            Text('No defences this day.',
                style: text.bodySmall?.copyWith(color: muted))
          else
            for (final d in selectedDefences) DefenceRow(defence: d),
        ],
      ),
    );

    final awaitingPanel = awaiting.isEmpty
        ? null
        : Panel(
            title: '${awaiting.length} '
                'defence${awaiting.length == 1 ? '' : 's'} awaiting a date',
            icon: Icons.event_busy_outlined,
            child: Column(
              key: const Key('awaitingDateHeading'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final d in awaiting) DefenceRow(defence: d)],
            ),
          );

    return KeyedSubtree(
      key: const Key('defenceCalendar'),
      child: SplitColumns(
        primaryFlex: 7,
        secondaryFlex: 5,
        stackBelow: 940,
        primary: [grid],
        secondary: [dayPanel, ?awaitingPanel],
      ),
    );
  }

  String _dayPanelHeading(DateTime day, DateTime today) {
    final base = '${_monthNames[day.month - 1]} ${day.day}, ${day.year}';
    return day == today ? '$base (Today)' : base;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppTokens.md,
      runSpacing: AppTokens.xs,
      children: [
        for (final status in DefenceStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: defenceStatusColor(status, brightness),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppTokens.xs),
              Text(defenceStatusLabel(status), style: text.labelSmall),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.defences,
    required this.brightness,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<Defence> defences;
  final Brightness brightness;
  final VoidCallback onTap;

  /// Dots never overflow however full a day gets: past this many, the
  /// remainder collapses into a "+N" label instead of a wider row.
  static const _maxDots = 4;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final scheme = Theme.of(context).colorScheme;
    final shown = defences.length > _maxDots
        ? defences.take(_maxDots).toList()
        : defences;
    final overflow = defences.length - shown.length;

    final count = defences.length;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${day.day}, '
          '${count == 0 ? 'no defences' : '$count defence${count == 1 ? '' : 's'}'}',
      excludeSemantics: true,
      child: InkWell(
        key: Key(_DefenceCalendarState._cellKey(day)),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 64,
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary
                : count > 0
                    ? scheme.primary.withValues(alpha: 0.06)
                    : null,
            border: isToday && !isSelected
                ? Border.all(color: scheme.primary, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                '${day.day}',
                style: text.labelLarge?.copyWith(
                  color: isSelected
                      ? scheme.onPrimary
                      : inMonth
                          ? null
                          : muted.withValues(alpha: 0.45),
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 10,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 3,
                  children: [
                    for (final d in shown)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.onPrimary
                              : defenceStatusColor(d.status, brightness),
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (overflow > 0)
                      Text('+$overflow',
                          style: TextStyle(
                              fontSize: 8,
                              color: isSelected ? scheme.onPrimary : muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
