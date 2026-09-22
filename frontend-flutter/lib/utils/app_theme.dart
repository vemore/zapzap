import 'package:flutter/material.dart';

/// The palette of the React client (`frontend/tailwind.config.js`), so both
/// clients look alike: slate surfaces, amber accent, a green card table.
abstract final class AppColors {
  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const slate400 = Color(0xFF94A3B8);
  static const slate100 = Color(0xFFF1F5F9);

  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);

  /// The table felt: Tailwind `green-900` / `green-800`, as in the game board.
  static const table = Color(0xFF14532D);
  static const tableLight = Color(0xFF166534);

  static const error = Color(0xFFEF4444);
}

/// The one theme of the app: dark, like the React client.
abstract final class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.amber400,
      onPrimary: AppColors.slate900,
      secondary: AppColors.amber500,
      onSecondary: AppColors.slate900,
      tertiary: AppColors.tableLight,
      onTertiary: AppColors.slate100,
      error: AppColors.error,
      onError: AppColors.slate100,
      surface: AppColors.slate800,
      onSurface: AppColors.slate100,
      surfaceContainerHighest: AppColors.slate700,
      onSurfaceVariant: AppColors.slate400,
      outline: AppColors.slate600,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.slate900,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.slate800,
        foregroundColor: AppColors.slate100,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.amber500,
          foregroundColor: AppColors.slate900,
          minimumSize: const Size(200, 48),
        ),
      ),
      cardTheme: const CardThemeData(color: AppColors.slate800),
    );
  }
}
