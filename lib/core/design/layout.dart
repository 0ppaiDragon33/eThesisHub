import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The three layout classes the app is designed for.
///
/// Each screen asks which one it is in and composes differently — a phone
/// is not a shrunken desktop.
enum Breakpoint {
  /// Under 720: bottom navigation, one stacked column.
  compact,

  /// 720–1199: icon rail, two columns where a screen has a side column.
  medium,

  /// 1200 and up: full sidebar, split workspaces.
  expanded;

  static const double mediumFrom = 720;
  static const double expandedFrom = 1200;

  static Breakpoint forWidth(double width) {
    if (width >= expandedFrom) return Breakpoint.expanded;
    if (width >= mediumFrom) return Breakpoint.medium;
    return Breakpoint.compact;
  }

  static Breakpoint of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);
}

/// A primary column and a narrower side column that stack below [stackBelow]
/// of available width.
///
/// Measures its own width rather than the screen's, so it behaves the same
/// inside the shell whether the sidebar is collapsed or not.
class SplitColumns extends StatelessWidget {
  const SplitColumns({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 8,
    this.secondaryFlex = 5,
    this.stackBelow = 860,
    this.gap = AppTokens.lg,
    this.secondaryFirstWhenStacked = false,
  });

  final List<Widget> primary;
  final List<Widget> secondary;
  final int primaryFlex;
  final int secondaryFlex;
  final double stackBelow;
  final double gap;

  /// On a phone, some side columns (the next deadline, say) matter more
  /// than the long list beside them.
  final bool secondaryFirstWhenStacked;

  static List<Widget> _spaced(List<Widget> children, double gap) => [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < stackBelow) {
          final first = secondaryFirstWhenStacked ? secondary : primary;
          final second = secondaryFirstWhenStacked ? primary : secondary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _spaced([...first, ...second], gap),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: primaryFlex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _spaced(primary, gap),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: secondaryFlex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _spaced(secondary, gap),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Short, human dates used across the rebuilt screens.
class Dates {
  const Dates._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String day(DateTime d) {
    final l = d.toLocal();
    return '${_months[l.month - 1]} ${l.day}, ${l.year}';
  }

  static String dayShort(DateTime d) {
    final l = d.toLocal();
    return '${_months[l.month - 1]} ${l.day}';
  }

  static String weekday(DateTime d) => _days[d.toLocal().weekday - 1];

  static String monthShort(DateTime d) => _months[d.toLocal().month - 1];

  static String time(DateTime d) {
    final l = d.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  static String dayTime(DateTime d) => '${dayShort(d)}, ${time(d)}';

  /// "Today", "Yesterday", "3 days ago", then a date.
  static String relative(DateTime d, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toLocal();
    final l = d.toLocal();
    final today = DateTime(n.year, n.month, n.day);
    final that = DateTime(l.year, l.month, l.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today, ${time(l)}';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return '$diff days ago';
    return day(l);
  }
}
