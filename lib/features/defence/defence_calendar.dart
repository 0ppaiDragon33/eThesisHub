import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const DefenceCalendar({super.key});

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
        if (defences.isEmpty) {
          return const EmptyState(
            key: Key('noDefences'),
            icon: Icons.forum_outlined,
            title: 'No defences scheduled',
            message: 'A defence appears here once the Coordinator schedules '
                'one you are part of.',
          );
        }
        return _buildCalendar(context, defences);
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

    return Column(
      key: const Key('defenceCalendar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Legend(brightness: brightness),
        const SizedBox(height: AppTokens.md),
        if (awaiting.isNotEmpty) ...[
          Text(
            key: const Key('awaitingDateHeading'),
            '${awaiting.length} defence${awaiting.length == 1 ? '' : 's'} '
            'awaiting a date',
            style: text.titleSmall,
          ),
          const SizedBox(height: AppTokens.sm),
          for (final d in awaiting) DefenceRow(defence: d),
          const SizedBox(height: AppTokens.md),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              key: const Key('calendarPrevMonth'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeMonth(-1),
            ),
            Text('${_monthNames[_month.month - 1]} ${_month.year}',
                style: text.titleMedium),
            IconButton(
              key: const Key('calendarNextMonth'),
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeMonth(1),
            ),
          ],
        ),
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
        const SizedBox(height: AppTokens.lg),
        Container(
          key: const Key('calendarDayPanel'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_dayPanelHeading(_selected, today), style: text.titleSmall),
              const SizedBox(height: AppTokens.sm),
              if (selectedDefences.isEmpty)
                Text('No defences this day.',
                    style: text.bodySmall?.copyWith(color: muted))
              else
                for (final d in selectedDefences) DefenceRow(defence: d),
            ],
          ),
        ),
      ],
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

    return GestureDetector(
      key: Key(_DefenceCalendarState._cellKey(day)),
      onTap: onTap,
      child: Container(
        height: 72,
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isToday ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: text.labelSmall?.copyWith(
                color: inMonth ? null : muted.withValues(alpha: 0.5),
                fontWeight: isToday ? FontWeight.bold : null,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 8,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                children: [
                  for (final d in shown)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: defenceStatusColor(d.status, brightness),
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (overflow > 0)
                    Text('+$overflow',
                        style: TextStyle(fontSize: 7, color: muted)),
                ],
              ),
            ),
            if (defences.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '${defences.length} defence${defences.length == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 7, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
