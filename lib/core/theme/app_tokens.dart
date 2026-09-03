import 'package:flutter/material.dart';

/// The design vocabulary, in one place.
///
/// This system's subject is paper: official forms that carry a reference
/// code, collect signatures, and move from the researchers to an adviser, to
/// the College Research Coordinator, to the Dean. The interface is built to
/// read the same way — a light page, restrained rules, and colour used to
/// mean something rather than to decorate.
///
/// Blue is the institution's mark and is spent only on things you can act
/// on. Approval and refusal get their own colours because they are the two
/// outcomes the whole system exists to record, and they must be legible at a
/// glance in a list of thirty theses.
///
/// A second, separate palette — `accents` — exists for tile badges and
/// chart series. Those identify rather than judge, so they carry no
/// meaning and must never be derived from a status. See the note above
/// the declarations.
class AppTokens {
  const AppTokens._();

  // --- Palette ------------------------------------------------------------
  // Warm near-black rather than pure black: the reference is printed ink on
  // paper, and #000 on white reads as screen glare at body sizes.
  static const ink = Color(0xFF14181F);
  static const inkMuted = Color(0xFF5A6472);

  /// ISUFST blue. Actions and the institutional mark, nothing else.
  static const seal = Color(0xFF0B5FA5);

  /// Accepted, recommended, approved. Fountain-pen green, not a success
  /// toast — the register is a signature, not a notification.
  static const endorsed = Color(0xFF1F6B4A);

  /// Declined, returned. A desaturated rubber-stamp red: this is a routine
  /// outcome in a research office, not an error, and colouring it like an
  /// alarm would misrepresent what happened.
  static const returned = Color(0xFFB4472F);

  /// Awaiting someone. Deliberately quiet — most things are waiting most of
  /// the time, so this must not compete with the two decided states.
  static const awaiting = Color(0xFF7A6A3F);

  static const paper = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF5F7F9);
  static const rule = Color(0xFFDDE2E8);

  // Dark counterparts. Light was designed first; these are tuned for the
  // same relationships (ink recedes, seal advances) rather than art-directed
  // separately.
  static const inkDark = Color(0xFFE6E9ED);
  static const inkMutedDark = Color(0xFF9BA5B4);
  static const sealDark = Color(0xFF6FB0E8);
  static const endorsedDark = Color(0xFF6FCFA0);
  static const returnedDark = Color(0xFFE89078);
  static const awaitingDark = Color(0xFFD8C48A);

  // --- Accents -----------------------------------------------------------
  // A second palette, for the one job the meaning colours above cannot do:
  // telling one thing from another without saying anything about it. A tile
  // badge and a chart segment identify; they do not judge.
  //
  // Three of these share a hue with a meaning colour on purpose — inventing
  // five unrelated hues would make the app look like a different product.
  // What keeps that safe is not separation on screen (a pine badge and an
  // `endorsed` chip do appear together) but separation by component: accents
  // live only in tile badges and chart segments, meaning colours only in
  // chips, buttons and text, and a badge's colour is fixed by its position
  // rather than derived from any status. Badges also carry an icon and chips
  // carry a word, so colour is never read alone.
  static const accentPlum = Color(0xFF5B4C8A);
  static const accentSeal = seal;
  static const accentPine = Color(0xFF1F6B4A);
  static const accentOchre = Color(0xFFB8722E);
  static const accentBrick = Color(0xFFB4472F);

  static const accentPlumDark = Color(0xFFA99AD4);
  static const accentSealDark = sealDark;
  static const accentPineDark = Color(0xFF6FCFA0);
  static const accentOchreDark = Color(0xFFDFA867);
  static const accentBrickDark = Color(0xFFE89078);

  /// Ordered, so a chart with n series indexes in rather than hard-coding.
  static const List<Color> accents = [
    accentPlum,
    accentSeal,
    accentPine,
    accentOchre,
    accentBrick,
  ];

  static const List<Color> accentsDark = [
    accentPlumDark,
    accentSealDark,
    accentPineDark,
    accentOchreDark,
    accentBrickDark,
  ];

  /// The accent for position [i] in the current brightness, wrapping if a
  /// caller asks for more series than there are accents.
  static Color accentFor(int i, Brightness brightness) {
    final list = brightness == Brightness.dark ? accentsDark : accents;
    return list[i % list.length];
  }

  static const paperDark = Color(0xFF161A20);
  static const surfaceDark = Color(0xFF1D222A);
  static const ruleDark = Color(0xFF2E3540);

  // --- Spacing ------------------------------------------------------------
  // A 4pt rhythm. Screens previously hand-rolled their own padding, which is
  // why one form overflowed a surface the others fitted.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Forms and documents read badly at full width. Everything sits in one
  /// measure so a screen does not change shape as you move through the flow.
  static const double measure = 620;

  /// Dashboards need more room than forms. Four tiles at the form measure
  /// would be 150px each, which is the compact step on a desktop.
  static const double measureWide = 1440;

  static const double radius = 10;
  static const double radiusSm = 6;
}
