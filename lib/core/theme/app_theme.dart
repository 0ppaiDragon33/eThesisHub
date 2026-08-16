import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The application theme.
///
/// Typography is deliberate in scale, weight and letter-spacing rather than
/// in typeface: no font files are bundled, so the family is the platform
/// default. The serif that the approved Form 1 layout uses belongs to the
/// PDF, which the `pdf` package renders independently of this theme.
///
/// Titles are set tight and heavy, body text is set loose and light — the
/// contrast between them is what gives a screen its structure, since there
/// is no second typeface to do that job.
class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        ink: AppTokens.ink,
        inkMuted: AppTokens.inkMuted,
        seal: AppTokens.seal,
        paper: AppTokens.paper,
        surface: AppTokens.surface,
        rule: AppTokens.rule,
        error: AppTokens.returned,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        ink: AppTokens.inkDark,
        inkMuted: AppTokens.inkMutedDark,
        seal: AppTokens.sealDark,
        paper: AppTokens.paperDark,
        surface: AppTokens.surfaceDark,
        rule: AppTokens.ruleDark,
        error: AppTokens.returnedDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color ink,
    required Color inkMuted,
    required Color seal,
    required Color paper,
    required Color surface,
    required Color rule,
    required Color error,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppTokens.seal,
      brightness: brightness,
    ).copyWith(
      primary: seal,
      onPrimary: brightness == Brightness.light
          ? AppTokens.paper
          : AppTokens.paperDark,
      surface: paper,
      onSurface: ink,
      surfaceContainerLowest: paper,
      surfaceContainer: surface,
      outlineVariant: rule,
      error: error,
    );

    final text = _typography(ink, inkMuted);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      textTheme: text,
      dividerTheme: DividerThemeData(color: rule, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // A hairline instead of a shadow: the app bar is a masthead on a
        // page, not a floating layer above it.
        shape: Border(bottom: BorderSide(color: rule)),
        titleTextStyle: text.titleMedium,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        color: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: rule),
          borderRadius: BorderRadius.circular(AppTokens.radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        // Filled fields with a hairline, not underlines: a form here is a
        // set of boxes to complete, which is how the paper original reads.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          borderSide: BorderSide(color: rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          borderSide: BorderSide(color: rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          borderSide: BorderSide(color: seal, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md,
          vertical: AppTokens.md,
        ),
        labelStyle: text.bodyMedium?.copyWith(color: inkMuted),
        helperStyle: text.bodySmall?.copyWith(color: inkMuted),
        helperMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: rule),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: inkMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        indicatorColor: seal.withValues(alpha: 0.14),
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: paper,
        indicatorColor: seal.withValues(alpha: 0.14),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: seal),
        unselectedLabelTextStyle:
            text.labelMedium?.copyWith(color: inkMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    );
  }

  /// Titles tighten as they grow; body text stays open. With one family
  /// doing every job, that divergence is what separates a heading from a
  /// paragraph at a glance.
  static TextTheme _typography(Color ink, Color inkMuted) {
    return TextTheme(
      headlineSmall: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 16, height: 1.5, color: ink),
      bodyMedium: TextStyle(
        fontSize: 15, height: 1.55, color: ink),
      bodySmall: TextStyle(
        fontSize: 13, height: 1.5, color: inkMuted),
      // Labels are the system's own voice — field names, chips, buttons.
      // Wide tracking and a small size keep them subordinate to content.
      labelLarge: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: inkMuted,
      ),
    );
  }
}
