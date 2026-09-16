import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart' show Gap;

/// The app's mark: a mortarboard inside a rounded square.
///
/// Drawn in code rather than shipped as an image (D81) so it stays sharp at
/// every size it appears — 56px on the entry brand pane, 28px in the phone
/// brand band — and so it can take the dark-mode seal without a second asset.
///
/// Seal blue, not the purple of the reference image: every primary button,
/// link and active destination in this app keys off `seal`, and a mark in a
/// colour used nowhere else reads as borrowed rather than designed.
class BrandEmblem extends StatelessWidget {
  const BrandEmblem({
    super.key,
    this.size = 44,
    this.foreground,
    this.background,
  });

  final double size;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? (dark ? AppTokens.sealDark : AppTokens.seal),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.school,
        size: size * 0.52,
        color: foreground ?? Colors.white,
      ),
    );
  }
}

/// The shared layout for every entry screen: login, register, verify-email,
/// no-profile and deactivated (D82).
///
/// Wide surfaces get the seal brand pane beside the form; narrow ones get a
/// band above it. The form sits in a card at both widths so it reads as one
/// object rather than as fields floating on a page.
///
/// The keyboard is never detected (D83). The band lives INSIDE the scroll
/// view and `resizeToAvoidBottomInset` keeps its default, so `Scaffold`
/// shrinks the viewport and a focused field's own `Scrollable.ensureVisible`
/// brings it into view. The band simply scrolls away once typing starts,
/// which is what gives register's five fields the full height without any
/// inset arithmetic.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// PLACEHOLDER, awaiting the owner's wording (spec §5).
  ///
  /// This is the first line a defence panel reads on a projector, so it is
  /// theirs to write. It lives here as a single constant precisely so that
  /// replacing it is a one-line change rather than an edit to five screens.
  static const String brandSentence =
      'Nomination, defence and the thesis record — '
      'in one place, for the whole college.';

  /// Above this width the brand pane sits beside the form; below it, above.
  static const double wideBreakpoint = 840;

  /// The maximum width of the form card.
  static const double cardMeasure = 420;

  @override
  Widget build(BuildContext context) {
    // resizeToAvoidBottomInset is deliberately not set: Flutter's default
    // (true) is the behaviour this design depends on.
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= wideBreakpoint;
          return wide ? _wide(context) : _narrow(context);
        },
      ),
    );
  }

  Widget _wide(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 42, child: _pane(context)),
        Expanded(
          flex: 58,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.lg),
            child: Center(child: _card(context)),
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    // The band is a child of the scroll view, not a sibling above it (D83).
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _band(context),
          Padding(
            padding: const EdgeInsets.all(AppTokens.md),
            child: _card(context),
          ),
        ],
      ),
    );
  }

  Widget _pane(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? AppTokens.sealDark : AppTokens.seal,
      padding: const EdgeInsets.all(AppTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const BrandEmblem(size: 56, background: Colors.white24),
          const Gap.md(),
          Text(
            'eThesisHub',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const Gap.sm(),
          Text(
            brandSentence,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _band(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? AppTokens.sealDark : AppTokens.seal,
      padding: const EdgeInsets.all(AppTokens.md),
      child: Row(
        children: [
          const BrandEmblem(size: 28, background: Colors.white24),
          const SizedBox(width: AppTokens.sm),
          Text(
            'eThesisHub',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: cardMeasure),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.lg),
        decoration: BoxDecoration(
          color: dark ? AppTokens.surfaceDark : AppTokens.paper,
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(color: dark ? AppTokens.ruleDark : AppTokens.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: AppTokens.sm),
              Text(
                subtitle!,
                style: text.bodySmall?.copyWith(
                  color: dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
                ),
              ),
            ],
            const Gap.md(),
            ...children,
          ],
        ),
      ),
    );
  }
}
