import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// A region of a workspace: a heading line and its content on paper.
///
/// Deliberately not a floating card — no shadow, a single hairline, and the
/// heading sits inside the border so a page of panels reads as one sheet
/// divided into parts. [flush] drops the inner padding for content that
/// draws its own rows edge to edge (tables, action lists).
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    required this.child,
    this.flush = false,
    this.emphasis = false,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Widget child;
  final bool flush;

  /// A seal edge on the left. Reserved for the one panel on a screen that
  /// holds the reader's next step.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final collapse = PanelCollapse.maybeOf(context);
    if (collapse != null && collapse.enabled && title != null) {
      return _CollapsiblePanel(panel: this, collapse: collapse);
    }
    return _frame(
      context,
      header: title != null || trailing != null ? _header(context) : null,
      body: _body(),
    );
  }

  Widget _body() => Padding(
        padding: flush ? EdgeInsets.zero : const EdgeInsets.all(AppTokens.lg - 4),
        child: child,
      );

  /// The heading row. [end] replaces [trailing] when given (a folded panel
  /// shows its peek and chevron there instead), and [showSubtitle] drops the
  /// subtitle from a folded one.
  Widget _header(
    BuildContext context, {
    Widget? end,
    bool showSubtitle = true,
  }) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final tail = end ?? trailing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.lg - 4, AppTokens.md, AppTokens.md, AppTokens.md),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: p.muted),
            const SizedBox(width: AppTokens.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  // Wraps rather than truncating: at a large text scale a
                  // one-line panel title lost its tail to an ellipsis, and a
                  // heading you cannot read is worse than one that takes a
                  // second line.
                  Text(title!,
                      style: text.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                if (showSubtitle && subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          if (tail != null) ...[
            const SizedBox(width: AppTokens.sm),
            tail,
          ],
        ],
      ),
    );
  }

  Widget _frame(
    BuildContext context, {
    required Widget? header,
    required Widget? body,
  }) {
    final p = Palette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(AppTokens.radius + 2),
        border: Border.all(color: p.rule),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radius + 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: emphasis
                ? Border(left: BorderSide(color: p.seal, width: 4))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?header,
              if (header != null && body != null)
                Divider(height: 1, color: p.rule),
              ?body,
            ],
          ),
        ),
      ),
    );
  }
}

/// Folds the [Panel]s beneath it into a single tappable row when [enabled]:
/// the title, a short [peek] value, and a chevron. Tapping opens the panel.
///
/// The dashboards set [enabled] on phone widths only (see `CollapseOnPhone`
/// in `overview_common.dart`), so a long page of charts and tables costs one
/// line each until the reader asks for one. Anywhere this is absent, or
/// [enabled] is false, a panel draws exactly as it always has.
class PanelCollapse extends InheritedWidget {
  const PanelCollapse({
    super.key,
    required this.enabled,
    required this.id,
    this.peek,
    this.initiallyOpen = false,
    this.openOn,
    required super.child,
  });

  final bool enabled;

  /// Names the panel's toggle for tests: `panelToggle-<id>`.
  final String id;

  /// A short value shown on the folded row ("2 defences", "24").
  final String? peek;

  final bool initiallyOpen;

  /// Opens the panel whenever this notifies, e.g. a filter picked elsewhere
  /// on the page that only this panel shows the result of.
  final Listenable? openOn;

  static PanelCollapse? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelCollapse>();

  @override
  bool updateShouldNotify(PanelCollapse old) =>
      enabled != old.enabled ||
      peek != old.peek ||
      id != old.id ||
      initiallyOpen != old.initiallyOpen ||
      openOn != old.openOn;
}

class _CollapsiblePanel extends StatefulWidget {
  const _CollapsiblePanel({required this.panel, required this.collapse});

  final Panel panel;
  final PanelCollapse collapse;

  @override
  State<_CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<_CollapsiblePanel> {
  late bool _open = widget.collapse.initiallyOpen;

  @override
  void initState() {
    super.initState();
    widget.collapse.openOn?.addListener(_openUp);
  }

  @override
  void didUpdateWidget(_CollapsiblePanel old) {
    super.didUpdateWidget(old);
    if (old.collapse.openOn != widget.collapse.openOn) {
      old.collapse.openOn?.removeListener(_openUp);
      widget.collapse.openOn?.addListener(_openUp);
    }
  }

  @override
  void dispose() {
    widget.collapse.openOn?.removeListener(_openUp);
    super.dispose();
  }

  void _openUp() {
    if (mounted && !_open) setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final peek = widget.collapse.peek;

    final end = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_open && panel.trailing != null) ...[
          panel.trailing!,
          const SizedBox(width: AppTokens.sm),
        ],
        if (!_open && peek != null && peek.isNotEmpty) ...[
          Text(
            peek,
            style: text.labelMedium?.copyWith(
              color: p.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppTokens.xs),
        ],
        AnimatedRotation(
          turns: _open ? 0.25 : 0,
          duration: const Duration(milliseconds: 180),
          child: Icon(Icons.chevron_right_rounded, color: p.muted),
        ),
      ],
    );

    final header = Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        key: Key('panelToggle-${widget.collapse.id}'),
        onTap: () => setState(() => _open = !_open),
        child: panel._header(context, end: end, showSubtitle: _open),
      ),
    );

    return panel._frame(
      context,
      header: header,
      body: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        // Panels inside this one draw normally, whatever is above.
        child: _open
            ? PanelCollapse(
                enabled: false,
                id: widget.collapse.id,
                child: panel._body(),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// A status word with its icon, tinted by [tone]. Never colour alone.
class ToneBadge extends StatelessWidget {
  const ToneBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.dense = false,
    this.textKey,
  });

  final String label;
  final Tone tone;
  final IconData? icon;
  final bool dense;

  /// Placed on the label text so tests and screen readers find the word.
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final c = tone.color(context);
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
            dense ? 6 : 8, dense ? 2 : 4, dense ? 8 : 10, dense ? 2 : 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? tone.icon, size: dense ? 13 : 15, color: c),
            SizedBox(width: dense ? 4 : 6),
            Flexible(
              child: Text(
                label,
                key: textKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: c,
                      fontSize: dense ? 12 : 13,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Initials in a circle, coloured by position-free hashing of the name so a
/// person keeps their colour across screens. Accents identify; they judge
/// nothing.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 36});

  final String name;
  final double size;

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hash = name.codeUnits.fold<int>(0, (a, b) => (a + b) & 0x7fffffff);
    final c = p.accent(hash);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Text(
          initialsOf(name),
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.36,
          ),
        ),
      ),
    );
  }
}

/// A person on a thesis: avatar, name, their part in it, and an optional
/// state on the right.
class PersonLine extends StatelessWidget {
  const PersonLine({
    super.key,
    required this.name,
    required this.role,
    this.trailing,
  });

  final String name;
  final String role;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
      child: Row(
        children: [
          InitialsAvatar(name),
          const SizedBox(width: AppTokens.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(role, style: text.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTokens.sm),
            Flexible(child: trailing!),
          ],
        ],
      ),
    );
  }
}

/// A label above a value, for record facts in a side column.
class FactLine extends StatelessWidget {
  const FactLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.md - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall),
          const SizedBox(height: 2),
          Text(value.isEmpty ? 'Not recorded' : value, style: text.bodyMedium),
        ],
      ),
    );
  }
}
