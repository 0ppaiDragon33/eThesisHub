import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// Shared record primitives for the rebuilt interface.
///
/// Lists are registers of rows with hover and focus states, grouped under a
/// section heading — not stacks of individual cards.

/// Opens a section: a sentence-case heading, an optional count or control,
/// and a short accent under the heading rather than a full-width rule.
class SectionRule extends StatelessWidget {
  const SectionRule(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.lg, bottom: AppTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: p.seal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppTokens.sm + 2),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One record in a register. Hover, press and keyboard focus all show.
class RecordRow extends StatelessWidget {
  const RecordRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  /// When null the row is plain content with no ink response — a row that
  /// looks interactive but does nothing is worse than one that plainly is
  /// not.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    final row = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md, vertical: AppTokens.md - 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppTokens.md - 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: text.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
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
          if (onTap != null) ...[
            const SizedBox(width: AppTokens.xs),
            Icon(Icons.chevron_right_rounded, color: p.muted, size: 20),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// A labelled field: the label above the input in sentence case, so every
/// form shares one rhythm whatever the input is.
class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;

  /// A short line under the label saying what belongs in the field.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: text.labelLarge?.copyWith(color: p.text)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: text.bodySmall),
          ],
          const SizedBox(height: AppTokens.sm - 2),
          child,
        ],
      ),
    );
  }
}

/// Label-and-value pairs, read in the order given. Two columns when there
/// is room; label above value when there is not.
class KeyFacts extends StatelessWidget {
  const KeyFacts(this.facts, {super.key});

  final List<({String label, String value})> facts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.hasBoundedWidth && constraints.maxWidth < 360;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final fact in facts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.sm + 2),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fact.label, style: text.labelSmall),
                          Text(fact.value, style: text.bodyMedium),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(fact.label, style: text.labelSmall),
                          ),
                          Expanded(
                            child: Text(fact.value, style: text.bodyMedium),
                          ),
                        ],
                      ),
              ),
          ],
        );
      },
    );
  }
}
