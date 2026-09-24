import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The application theme — version 2.
///
/// The palette in [AppTokens] is unchanged; everything built on it is new.
/// The canvas is now the light surface grey and content sits on paper
/// panels above it, the navigation column is ink, and type carries a wider
/// scale with two voices: Source Serif 4 for the things being recorded
/// (page titles, thesis titles, figures) and the platform sans for the
/// interface around them (labels, panel headings, buttons, tables).
///
/// Labels are sentence case at a readable size. The previous system's
/// tracked-out capitals are gone.
class AppTheme {
  /// The bundled serif (SIL OFL 1.1, `assets/fonts/`).
  static const String serif = 'SourceSerif4';

  static ThemeData get light => _build(
        brightness: Brightness.light,
        ink: AppTokens.ink,
        inkMuted: AppTokens.inkMuted,
        seal: AppTokens.seal,
        paper: AppTokens.paper,
        canvas: AppTokens.surface,
        rule: AppTokens.rule,
        error: AppTokens.returned,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        ink: AppTokens.inkDark,
        inkMuted: AppTokens.inkMutedDark,
        seal: AppTokens.sealDark,
        paper: AppTokens.surfaceDark,
        canvas: AppTokens.paperDark,
        rule: AppTokens.ruleDark,
        error: AppTokens.returnedDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color ink,
    required Color inkMuted,
    required Color seal,
    required Color paper,
    required Color canvas,
    required Color rule,
    required Color error,
  }) {
    final light = brightness == Brightness.light;
    final onSeal = light ? AppTokens.paper : AppTokens.paperDark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppTokens.seal,
      brightness: brightness,
    ).copyWith(
      primary: seal,
      onPrimary: onSeal,
      primaryContainer: seal.withValues(alpha: 0.12),
      onPrimaryContainer: ink,
      secondary: seal,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      surfaceContainerLowest: paper,
      surfaceContainerLow: paper,
      surfaceContainer: canvas,
      surfaceContainerHigh: canvas,
      outline: rule,
      outlineVariant: rule,
      error: error,
      onError: onSeal,
    );

    final text = _typography(ink, inkMuted);
    const r8 = BorderRadius.all(Radius.circular(8));
    const r12 = BorderRadius.all(Radius.circular(12));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: paper,
      textTheme: text,
      visualDensity: VisualDensity.standard,
      focusColor: seal.withValues(alpha: 0.14),
      hoverColor: seal.withValues(alpha: 0.05),
      dividerTheme: DividerThemeData(color: rule, thickness: 1, space: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleSmall,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        color: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: AppTokens.sm + 4),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: rule),
          borderRadius: r12,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        isDense: false,
        border: OutlineInputBorder(
          borderRadius: r8,
          borderSide: BorderSide(color: rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: r8,
          borderSide: BorderSide(color: rule, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: r8,
          borderSide: BorderSide(color: seal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: r8,
          borderSide: BorderSide(color: error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: r8,
          borderSide: BorderSide(color: error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md - 2,
          vertical: AppTokens.md - 2,
        ),
        labelStyle: text.bodyMedium?.copyWith(color: inkMuted),
        floatingLabelStyle: text.labelMedium?.copyWith(color: seal),
        hintStyle: text.bodyMedium?.copyWith(color: inkMuted),
        helperStyle: text.bodySmall,
        helperMaxLines: 3,
        errorMaxLines: 3,
        prefixIconColor: inkMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Size(64, 48), never Size.fromHeight: 48dp is the touch-target
          // floor, and an infinite minimum width
          // throws inside a Row. Buttons that should fill a line still do
          // inside a stretched Column.
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const RoundedRectangleBorder(borderRadius: r8),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          elevation: 0,
          backgroundColor: paper,
          foregroundColor: seal,
          shape: RoundedRectangleBorder(
            borderRadius: r8,
            side: BorderSide(color: rule),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          foregroundColor: ink,
          backgroundColor: paper,
          side: BorderSide(color: rule, width: 1.2),
          shape: const RoundedRectangleBorder(borderRadius: r8),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          foregroundColor: seal,
          shape: const RoundedRectangleBorder(borderRadius: r8),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: inkMuted,
          shape: const RoundedRectangleBorder(borderRadius: r8),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: paper,
          selectedBackgroundColor: seal.withValues(alpha: 0.12),
          selectedForegroundColor: seal,
          foregroundColor: inkMuted,
          side: BorderSide(color: rule),
          textStyle: text.labelMedium,
          shape: const RoundedRectangleBorder(borderRadius: r8),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: paper,
        selectedColor: seal.withValues(alpha: 0.12),
        side: BorderSide(color: rule),
        labelStyle: text.labelMedium?.copyWith(color: ink),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: seal),
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: seal,
        unselectedLabelColor: inkMuted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicatorColor: seal,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: rule,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelMedium?.copyWith(color: inkMuted),
        dataTextStyle: text.bodyMedium,
        headingRowHeight: 44,
        dataRowMinHeight: 56,
        dataRowMaxHeight: 72,
        horizontalMargin: AppTokens.lg - 4,
        columnSpacing: AppTokens.xl,
        dividerThickness: 1,
        headingRowColor: WidgetStatePropertyAll(canvas),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall,
        iconColor: inkMuted,
        shape: const RoundedRectangleBorder(borderRadius: r8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: seal.withValues(alpha: 0.14),
        indicatorShape: const RoundedRectangleBorder(borderRadius: r8),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            fontSize: 11.5,
            letterSpacing: 0,
            overflow: TextOverflow.ellipsis,
            color: s.contains(WidgetState.selected) ? seal : inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? seal : inkMuted,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: r12,
          side: BorderSide(color: rule),
        ),
        textStyle: text.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: light ? AppTokens.ink : AppTokens.inkDark,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        textStyle: text.bodySmall?.copyWith(
          color: light ? AppTokens.paper : AppTokens.paperDark,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: seal,
        linearTrackColor: rule,
        circularTrackColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: light ? AppTokens.returned : AppTokens.returnedDark,
        textColor: onSeal,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: light ? AppTokens.ink : AppTokens.inkDark,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: light ? AppTokens.paper : AppTokens.paperDark,
        ),
        shape: const RoundedRectangleBorder(borderRadius: r8),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4))),
        side: BorderSide(color: inkMuted, width: 1.5),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: seal,
        collapsedIconColor: inkMuted,
        tilePadding: EdgeInsets.zero,
      ),
    );
  }

  static TextTheme _typography(Color ink, Color inkMuted) {
    return TextTheme(
      // Display: page titles and the thesis title on its workspace.
      headlineLarge: TextStyle(
        fontFamily: serif,
        fontSize: 36,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: serif,
        fontSize: 30,
        height: 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: serif,
        fontSize: 24,
        height: 1.22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: ink,
      ),
      // Record titles: a thesis in a list, a chapter name.
      titleLarge: TextStyle(
        fontFamily: serif,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontFamily: serif,
        fontSize: 17,
        height: 1.32,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      // Interface headings: panel titles. Sans, so structure and content
      // never read as the same kind of thing.
      titleSmall: TextStyle(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14.5, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 13, height: 1.45, color: inkMuted),
      labelLarge: const TextStyle(
          fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: 0),
      labelMedium: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0),
      labelSmall: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: inkMuted,
      ),
    );
  }
}
