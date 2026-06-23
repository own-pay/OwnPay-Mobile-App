import 'package:flutter/material.dart';

/// Brand + semantic colors (see DESIGN.md §2). Status semantics are consistent app-wide:
/// teal = brand, green = synced/confirmed, amber = pending, red = failed/blocked.
class AppColors {
  const AppColors._();

  static const Color brand = Color(0xFF0D9488); // teal
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
}

/// Material 3 light/dark themes seeded from the OwnPay brand teal.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: brightness,
        ),
      );
}
