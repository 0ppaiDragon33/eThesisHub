import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The single page layout.
///
/// Every screen previously hand-rolled its own `Center` + `ConstrainedBox` +
/// `SingleChildScrollView` with its own padding and its own width, which is
/// why one form overflowed a test surface the others fitted and why moving
/// between screens shifted the content sideways. One measure, one rhythm,
/// one scroll behaviour.
///
/// Scrolls by default: these are forms, and a form that cannot scroll puts
/// its submit button off-screen on a phone.
class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.scrollable = true,
  });

  /// Optional page heading, set above the content. Distinct from the app bar
  /// title: the app bar names where you are in the app, this names what the
  /// page is asking of you.
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: text.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: AppTokens.sm),
            Text(subtitle!, style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: AppTokens.lg),
        ],
        ...children,
      ],
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTokens.measure),
        child: scrollable
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(AppTokens.lg),
                child: column,
              )
            : Padding(
                padding: const EdgeInsets.all(AppTokens.lg),
                child: column,
              ),
      ),
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
