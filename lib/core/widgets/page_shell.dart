import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// The page frame every signed-in screen renders inside the shell.
///
/// A header band (context line, title, one-sentence purpose, and the page's
/// own actions on the right) above a content column. The shell's top bar
/// only says where you are; this header says what the page asks of you.
///
/// Scrolls by default: most pages are forms or registers, and a form that
/// cannot scroll puts its submit button off-screen on a phone.
class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.children,
    this.kicker,
    this.title,
    this.subtitle,
    this.actions = const [],
    this.scrollable = true,
    this.maxWidth = AppTokens.measure,
  });

  /// The context the page is read in — the record it belongs to, or the
  /// office whose queue it is. Sentence case, set small above the title.
  final String? kicker;
  final String? title;
  final String? subtitle;

  /// Page-level commands, drawn at the header's right edge (or under the
  /// title on a phone). Keep to one filled button at most.
  final List<Widget> actions;

  final List<Widget> children;
  final bool scrollable;

  /// Forms stay at [AppTokens.measure]; dashboards and registers pass
  /// [AppTokens.measureWide].
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final compact = Breakpoint.of(context) == Breakpoint.compact;
    // Horizontal padding is `lg` at every width and sits INSIDE the
    // `maxWidth` cap, so a page's content measure is `maxWidth` minus this
    // padding — not `maxWidth` itself. The cap is a reading measure: adding
    // the padding back onto it (as an earlier revision did) widens every
    // page past the measure the token names.
    final pad = EdgeInsets.fromLTRB(
      AppTokens.lg,
      compact ? AppTokens.md : AppTokens.lg,
      AppTokens.lg,
      AppTokens.xl,
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (title != null || kicker != null || actions.isNotEmpty) ...[
          PageHeader(
            kicker: kicker,
            title: title,
            subtitle: subtitle,
            actions: actions,
          ),
          SizedBox(height: compact ? AppTokens.md : AppTokens.lg),
        ],
        ...children,
      ],
    );

    final body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: scrollable
            ? SingleChildScrollView(padding: pad, child: column)
            : Padding(padding: pad, child: column),
      ),
    );

    return ColoredBox(color: Palette.of(context).canvas, child: body);
  }
}

/// The header band of a [PageShell], usable on its own by screens that lay
/// out their own body.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    this.kicker,
    this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String? kicker;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final compact = Breakpoint.of(context) == Breakpoint.compact;

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kicker != null) ...[
          Text(kicker!,
              style: text.labelMedium?.copyWith(color: p.seal)),
          const SizedBox(height: AppTokens.xs),
        ],
        if (title != null)
          Text(title!,
              style: compact ? text.headlineSmall : text.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppTokens.xs + 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(subtitle!,
                style: text.bodyMedium?.copyWith(color: p.muted)),
          ),
        ],
      ],
    );

    final lead = leading == null
        ? words
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading!,
              const SizedBox(width: AppTokens.md),
              Expanded(child: words),
            ],
          );

    if (actions.isEmpty) return lead;

    final actionWrap = Wrap(
      spacing: AppTokens.sm,
      runSpacing: AppTokens.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          lead,
          const SizedBox(height: AppTokens.md),
          actionWrap,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: lead),
        const SizedBox(width: AppTokens.lg),
        Flexible(child: Align(alignment: Alignment.bottomRight, child: actionWrap)),
      ],
    );
  }
}

/// Vertical rhythm between blocks on a page. Named so screens stop inventing
/// their own gap sizes.
class Gap extends StatelessWidget {
  const Gap.sm({super.key}) : _h = AppTokens.sm;
  const Gap.md({super.key}) : _h = AppTokens.md;
  const Gap.lg({super.key}) : _h = AppTokens.lg;
  const Gap.xl({super.key}) : _h = AppTokens.xl;

  final double _h;

  @override
  Widget build(BuildContext context) => SizedBox(height: _h);
}
