import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The meaning palette, as one enum the whole UI speaks.
///
/// Every status badge, action row and timeline node resolves its colour
/// through [Tone] rather than reaching for [AppTokens] directly, so the
/// light/dark pairing is decided once. Colours are never used alone: every
/// consumer pairs a tone with an icon and a word.
enum Tone {
  /// Something the reader can act on. Institutional blue.
  act,

  /// Accepted, approved, endorsed.
  endorsed,

  /// Declined, returned.
  returned,

  /// Waiting on somebody.
  awaiting,

  /// Nobody's responsibility yet, or finished and inert.
  neutral;

  Color color(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      Tone.act => dark ? AppTokens.sealDark : AppTokens.seal,
      Tone.endorsed => dark ? AppTokens.endorsedDark : AppTokens.endorsed,
      Tone.returned => dark ? AppTokens.returnedDark : AppTokens.returned,
      Tone.awaiting => dark ? AppTokens.awaitingDark : AppTokens.awaiting,
      Tone.neutral => dark ? AppTokens.inkMutedDark : AppTokens.inkMuted,
    };
  }

  /// The default glyph for this tone, used when a caller has no more
  /// specific icon to offer.
  IconData get icon => switch (this) {
        Tone.act => Icons.arrow_circle_right_outlined,
        Tone.endorsed => Icons.check_circle_outline,
        Tone.returned => Icons.undo_rounded,
        Tone.awaiting => Icons.schedule_outlined,
        Tone.neutral => Icons.radio_button_unchecked,
      };
}

/// Brightness-aware access to the neutral tokens, so widgets stop writing
/// `dark ? AppTokens.x : AppTokens.y` by hand.
class Palette {
  const Palette._(this._dark);

  factory Palette.of(BuildContext context) =>
      Palette._(Theme.of(context).brightness == Brightness.dark);

  final bool _dark;

  bool get isDark => _dark;
  Color get text => _dark ? AppTokens.inkDark : AppTokens.ink;
  Color get muted => _dark ? AppTokens.inkMutedDark : AppTokens.inkMuted;
  Color get rule => _dark ? AppTokens.ruleDark : AppTokens.rule;
  Color get paper => _dark ? AppTokens.surfaceDark : AppTokens.paper;
  Color get canvas => _dark ? AppTokens.paperDark : AppTokens.surface;
  Color get seal => _dark ? AppTokens.sealDark : AppTokens.seal;

  /// The navigation column. Ink in light mode: the one dark mass on the
  /// page, so the working area reads as the paper it sits beside.
  Color get sidebar => _dark ? const Color(0xFF0F1216) : AppTokens.ink;
  Color get sidebarText => AppTokens.inkDark;
  Color get sidebarMuted => AppTokens.inkMutedDark;
  Color get sidebarRule => AppTokens.ruleDark;

  Color accent(int i) =>
      AppTokens.accentFor(i, _dark ? Brightness.dark : Brightness.light);
}
