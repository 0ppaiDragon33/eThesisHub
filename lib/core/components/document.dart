import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The shared presentation primitives for the document direction (D78).
///
/// Content sits on ruled rows under a hard section rule rather than inside
/// nested bordered panels: the tokens are already a paper-and-ink set, and
/// the app shell is itself a panel, so panels inside it become boxes within
/// boxes. Screens compose these instead of hand-rolling a Card with a
/// ListTile, which is the direct cause of every list in the app looking
/// slightly different from every other.

/// Opens a band: an overline label, an optional trailing count or control,
/// and the hard rule that separates this band from the one above it.
class SectionRule extends StatelessWidget {
  const SectionRule(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.lg, bottom: AppTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? AppTokens.inkMutedDark
                            : AppTokens.inkMuted,
                      ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppTokens.sm),
          Container(
            height: 1.5,
            color: dark ? AppTokens.inkDark : AppTokens.ink,
          ),
        ],
      ),
    );
  }
}

/// One record in a list: the ruled row that replaces Card-wrapping-ListTile.
///
/// The hairline is on the BOTTOM only, so consecutive rows read as a register
/// rather than as a stack of separate objects, and the last row sits flush
/// against whatever follows it.
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

  /// When null the row renders as plain content with no ink response — a row
  /// that looks interactive but does nothing is worse than one that plainly
  /// is not.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: dark ? AppTokens.ruleDark : AppTokens.rule,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppTokens.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(
                      color: dark
                          ? AppTokens.inkMutedDark
                          : AppTokens.inkMuted,
                    ),
                  ),
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
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// A labelled field: an overline label above the input, not floating inside
/// it.
///
/// Screens previously passed their own `InputDecoration(labelText: ...)` per
/// field, which is why no two forms in this app look alike. The label moves
/// out of the decoration and into the layout, so every form shares one
/// rhythm and the field itself is free to be a TextField, a dropdown or a
/// date picker without the label treatment changing.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  color: dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
                ),
          ),
          const SizedBox(height: AppTokens.sm),
          child,
        ],
      ),
    );
  }
}

/// Label-and-value pairs for stating facts about a record.
///
/// Takes an ordered list rather than a Map: these are read in a deliberate
/// order (program before academic year), and a Map's iteration order is an
/// implementation detail to rely on by accident.
class KeyFacts extends StatelessWidget {
  const KeyFacts(this.facts, {super.key});

  final List<({String label, String value})> facts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final fact in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    fact.label,
                    style: text.bodySmall?.copyWith(
                      color:
                          dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
                    ),
                  ),
                ),
                Expanded(child: Text(fact.value, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
