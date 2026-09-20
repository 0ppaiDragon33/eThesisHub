import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// The one greeting, for all four overviews.
///
/// It was copied verbatim into `student_overview.dart`,
/// `faculty_overview.dart`, `dean_overview.dart` and
/// `coordinator_overview.dart` -- four places for a future edit to miss on
/// the one element spec §6 says must never regress.
///
/// **Nothing here blocks on the profile document.** `currentUserProvider` is
/// read with `valueOrNull`, so a missing or still-loading `users/{uid}`
/// yields a plain "Good day" and the overview renders anyway. Gating a
/// control on that document existing is exactly what locked a leader out of
/// uploads in M2, and spec §6 names it.
///
/// There is no separate given-name field and no honorific, so the first
/// whitespace-separated token of `fullName` is the whole of it.
///
/// The greeting itself follows the time of day: "Good morning" before
/// 12:00, "Good afternoon" from 12:00 up to (not including) 18:00, and
/// "Good evening" from 18:00 on. "Good evening" rather than "Good night" --
/// "Good night" is a farewell in English, not a greeting, and this greets
/// someone arriving at the app. [now] defaults to [DateTime.now] and is
/// only ever overridden by a test, which pins the clock instead of racing
/// it.
class OverviewGreeting extends ConsumerWidget {
  const OverviewGreeting({super.key, this.now = DateTime.now});

  final DateTime Function() now;

  static String _band(DateTime at) {
    if (at.hour < 12) return 'Good morning';
    if (at.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String textFor(String fullName, DateTime at) {
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    final greeting = _band(at);
    return first.isEmpty ? greeting : '$greeting, $first';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUserProvider).valueOrNull?.fullName ?? '';
    final compact = Breakpoint.of(context) == Breakpoint.compact;
    final text = Theme.of(context).textTheme;
    return Text(
      textFor(name, now()),
      style: compact ? text.headlineSmall : text.headlineMedium,
    );
  }
}

/// The top of every overview: today's date and the reader's office, the
/// greeting, a one-line state of affairs, and the page's own commands.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.office,
    required this.summary,
    this.actions = const [],
    this.now = DateTime.now,
    this.animateKey,
  });

  /// When this changes, the office line cross-fades (the faculty mode).
  final Object? animateKey;

  /// Whose desk this is: "Student researcher", "Research office", ….
  final String office;
  final Widget summary;
  final List<Widget> actions;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final at = now();
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    return _layout(context, at, p, text);
  }

  Widget _layout(BuildContext context, DateTime at, Palette p, TextTheme text) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) =>
              FadeTransition(opacity: a, child: child),
          child: Text(
            '${Dates.weekday(at)}, ${Dates.day(at)} · $office',
            key: ValueKey(animateKey ?? office),
            style: text.labelMedium?.copyWith(color: p.seal),
          ),
        ),
        const SizedBox(height: AppTokens.xs),
        OverviewGreeting(now: now),
        const SizedBox(height: AppTokens.xs + 2),
        summary,
      ],
    );
    if (actions.isEmpty) return words;
    final compact = Breakpoint.of(context) == Breakpoint.compact;
    final wrap = Wrap(
      spacing: AppTokens.sm,
      runSpacing: AppTokens.sm,
      children: actions,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [words, const SizedBox(height: AppTokens.md), wrap],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: words),
        const SizedBox(width: AppTokens.lg),
        Flexible(
          child: Align(alignment: Alignment.bottomRight, child: wrap),
        ),
      ],
    );
  }
}

/// Canonical dashboard body: a wide canvas with a consistent gap between
/// blocks.
class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      maxWidth: AppTokens.measureWide,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTokens.lg),
          // Blocks settle in top to bottom, a beat apart.
          FadeIn(
            delay: Duration(milliseconds: 40 * (i < 5 ? i : 5)),
            child: children[i],
          ),
        ],
      ],
    );
  }
}

/// Defences scheduled within the next 7 days, today included.
///
/// One definition, for the faculty, dean and coordinator "Defences this
/// week" tiles. It existed three times -- a `FutureProvider` in
/// `faculty_overview.dart` and two byte-identical static methods -- and all
/// three carried the same bug: they counted **cancelled** and **completed**
/// defences as defences this week, so a defence called off on Monday still
/// showed on three dashboards on Tuesday. The student's own "next defence"
/// filtered `!d.status.isTerminal` correctly all along; this now agrees
/// with it.
///
/// A pure function over a list rather than a provider: the three callers
/// read three DIFFERENT sources (`myDefencesProvider` for faculty,
/// `allDefencesProvider` for the two college-wide roles, which the rules
/// permit only to them), and folding those into one shared provider would
/// put a college-wide read on a faculty surface.
///
/// [now] is injectable so a test can pin the window instead of racing the
/// clock.
List<Defence> defencesThisWeek(List<Defence> defences, {DateTime? now}) {
  final today0 = now ?? DateTime.now();
  final today = DateTime(today0.year, today0.month, today0.day);
  final end = today.add(const Duration(days: 7));
  return defences.where((d) {
    if (d.status.isTerminal) return false;
    final at = d.scheduledAt;
    if (at == null) return false;
    final day = DateTime(at.year, at.month, at.day);
    return !day.isBefore(today) && day.isBefore(end);
  }).toList();
}

/// What "active theses" means, for the dean and coordinator tile AND for the
/// stage donut a few hundred pixels below it on the same screen.
///
/// The two used to disagree: the tile was `allTheses.length` while the donut
/// broke `titleRejected` out into its own "Returned" bucket, so a reader
/// could see one number claim a thesis was active and the chart imply it was
/// not. The definition chosen here is **every thesis on file**, returned
/// ones included, because no `ThesisStatus` in this system is terminal --
/// `titleRejected` means "resubmit a new title set", which is a thesis
/// needing work, not a closed one. With this definition the donut's five
/// buckets sum to exactly the tile's figure, which is the property that
/// makes the two agree by construction rather than by coincidence.
int activeThesisCount(List<Thesis> all) => all.length;
