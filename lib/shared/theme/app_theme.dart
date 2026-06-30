import 'package:flutter/material.dart';

/// Brand + semantic colors (see DESIGN.md §2), tuned to the dark "console" look.
///
/// Status semantics are consistent app-wide: teal = brand/accent, green = synced/confirmed,
/// amber = pending, red = failed/blocked. The surface ramp (bg → surface → surfaceAlt) gives the
/// layered dark cards seen throughout the app.
class AppColors {
  const AppColors._();

  // Brand / accent.
  static const Color brand = Color(0xFF15E0BD); // bright teal-mint (buttons, pills, overlines, active nav)
  static const Color onBrand = Color(0xFF052B24); // dark text/icon on a brand-filled surface

  // Surfaces (dark ramp).
  static const Color bg = Color(0xFF0A0E18); // app background (near-black navy)
  static const Color surface = Color(0xFF121826); // cards / sheets
  static const Color surfaceAlt = Color(0xFF161D2D); // inputs / nested tiles / badges
  static const Color outline = Color(0xFF232B3D); // hairline borders

  // Text.
  static const Color textHi = Color(0xFFEDF1F7); // headings / primary text
  static const Color textMuted = Color(0xFF8A94A8); // secondary / captions

  // Semantic status.
  static const Color success = Color(0xFF16C088); // synced / confirmed
  static const Color warning = Color(0xFFE0A23C); // pending / queued
  static const Color danger = Color(0xFFF2596B); // failed / destructive / blocked
}

/// The OwnPay Console visual theme — a single cohesive **dark** theme matching the product mockups.
///
/// One theme, always dark (the app is forced to [ThemeMode.dark] in `app.dart`): the console aesthetic
/// is part of the product identity, and the SMS-monitoring surfaces are designed for the dark palette.
class AppTheme {
  const AppTheme._();

  /// Letter-spaced uppercase overline used for section labels ("RECENT PAYMENTS", "TODAY RECEIVED",
  /// "PERMISSION DISCLOSURE"). Brand-teal by default; callers may recolor.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: AppColors.brand,
  );

  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.brand,
      onPrimary: AppColors.onBrand,
      secondary: AppColors.brand,
      surface: AppColors.surface,
      onSurface: AppColors.textHi,
      onSurfaceVariant: AppColors.textMuted,
      outline: AppColors.outline,
      error: AppColors.danger,
      tertiary: AppColors.success,
    );

    final TextTheme text = Typography.whiteMountainView.apply(
      bodyColor: AppColors.textHi,
      displayColor: AppColors.textHi,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      textTheme: text,
      dividerColor: AppColors.outline,
      dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1, thickness: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          disabledBackgroundColor: AppColors.surfaceAlt,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textHi,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.outline),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: TextStyle(color: AppColors.textHi),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.brand),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? AppColors.onBrand : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? AppColors.brand : AppColors.surfaceAlt),
        trackOutlineColor: WidgetStateProperty.all<Color>(AppColors.outline),
      ),
    );
  }
}
