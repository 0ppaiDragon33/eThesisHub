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
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final hasHeader = title != null || trailing != null;

    final header = hasHeader
        ? Padding(
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
                        // Wraps rather than truncating: at a large text
                        // scale a one-line panel title lost its tail to an
                        // ellipsis, and a heading you cannot read is worse
                        // than one that takes a second line.
                        Text(title!,
                            style: text.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppTokens.sm),
                  trailing!,
                ],
              ],
            ),
          )
        : null;

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
              if (header != null) header,
              if (header != null) Divider(height: 1, color: p.rule),
              Padding(
                padding: flush
                    ? EdgeInsets.zero
                    : const EdgeInsets.all(AppTokens.lg - 4),
                child: child,
              ),
            ],
          ),
        ),
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
