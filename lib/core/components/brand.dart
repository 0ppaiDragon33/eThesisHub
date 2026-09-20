import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

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
/// no-profile and deactivated.
///
/// Wide surfaces split into a seal-blue route panel — the desks a thesis
/// passes through, drawn as the stamped route it is — and the form on the
/// canvas beside it. Narrow surfaces get a short seal header that scrolls
/// away with the form, so the keyboard never fights a fixed band.
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

  static const String brandSentence =
      'Nomination, defence and the thesis record — '
      'in one place, for the whole college.';

  /// Above this width the route panel sits beside the form.
  static const double wideBreakpoint = 900;

  /// The maximum width of the form column.
  static const double cardMeasure = 420;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.of(context).canvas,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(flex: 11, child: _RoutePanel()),
        Expanded(
          flex: 10,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTokens.xl),
                child: _form(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: p.isDark ? AppTokens.surfaceDark : AppTokens.seal,
            padding: EdgeInsets.fromLTRB(
              AppTokens.lg,
              MediaQuery.paddingOf(context).top + AppTokens.lg,
              AppTokens.lg,
              AppTokens.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandEmblem(size: 32, background: Colors.white24),
                    const SizedBox(width: AppTokens.sm + 2),
                    Text(
                      'eThesisHub',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.md),
                Text(
                  brandSentence,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.lg),
            child: Align(
              alignment: Alignment.topCenter,
              child: _form(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: cardMeasure),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: text.headlineMedium),
          if (subtitle != null) ...[
            const SizedBox(height: AppTokens.sm),
            Text(subtitle!, style: text.bodyMedium?.copyWith(color: p.muted)),
          ],
          const SizedBox(height: AppTokens.xl - 4),
          ...children,
        ],
      ),
    );
  }
}

/// The wide entry panel: the institution's mark, the product sentence, and
/// the route a thesis takes — five desks, each stamped in turn.
class _RoutePanel extends StatelessWidget {
  const _RoutePanel();

  static const _desks = [
    (Icons.groups_outlined, 'Researchers', 'Form the group, name the working title'),
    (Icons.school_outlined, 'Adviser and panel', 'Accept the nomination, judge the titles'),
    (Icons.inventory_2_outlined, 'Research Coordinator', 'Recommend and schedule'),
    (Icons.gavel_outlined, 'Dean', 'Approve and close each defence'),
    (Icons.local_library_outlined, 'College archive', 'The finished manuscript, on record'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.72);

    return Container(
      color: p.isDark ? AppTokens.surfaceDark : AppTokens.seal,
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandEmblem(size: 40, background: Colors.white24),
              const SizedBox(width: AppTokens.md - 4),
              Text('eThesisHub',
                  style: text.titleLarge
                      ?.copyWith(color: white, fontWeight: FontWeight.w700)),
            ],
          ),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              brandSentenceDisplay,
              style: text.headlineLarge?.copyWith(color: white),
            ),
          ),
          const SizedBox(height: AppTokens.xl),
          for (var i = 0; i < _desks.length; i++)
            _DeskStep(
              icon: _desks[i].$1,
              title: _desks[i].$2,
              detail: _desks[i].$3,
              last: i == _desks.length - 1,
              soft: soft,
            ),
          const Spacer(),
          Text(
            'Iloilo State University of Fisheries Science and Technology',
            style: text.bodySmall?.copyWith(color: soft),
          ),
        ],
      ),
    );
  }

  static const brandSentenceDisplay =
      'Every thesis, from nomination to the archive.';
}

class _DeskStep extends StatelessWidget {
  const _DeskStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.last,
    required this.soft,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool last;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                ),
                child: Icon(icon, size: 17, color: Colors.white),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : AppTokens.md + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(title,
                      style: text.labelLarge?.copyWith(color: Colors.white)),
                  Text(detail, style: text.bodySmall?.copyWith(color: soft)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
