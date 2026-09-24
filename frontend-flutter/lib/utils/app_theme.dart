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

  /// The casino felt of the game board: a radial green, lit at the centre
  /// and dark at the edges, under a painted texture and a watermark.
  static const feltCenter = Color(0xFF1C7A45);
  static const feltEdge = Color(0xFF0B3B1F);

  /// The texture's fibres, lighter and darker than the felt.
  static const feltFleckLight = Color(0x14FFFFFF);
  static const feltFleckDark = Color(0x1F000000);

  /// The ZapZap mark printed faintly at the centre of the felt.
  static const feltWatermark = Color(0x1AFFFFFF);

  /// The dark wood rim around the felt, and the thin inlay between them.
  static const rimLight = Color(0xFF5B3A22);
  static const rimDark = Color(0xFF2B170B);
  static const rimInlay = Color(0xFF8A6A3A);

  static const error = Color(0xFFEF4444);
}

/// The sizes of the cards on the board, in logical pixels: big enough to
/// read a rank and tap a card on a phone, with 48 px of every card in the
/// hand left uncovered — the least tap target Material asks for.
abstract final class CardSizes {
  /// The hand's cards take a quarter of its width, within these bounds.
  static const handMin = 76.0;
  static const handMax = 96.0;

  /// The least width of a hand card the next one leaves visible; a hand
  /// that cannot keep it on one row goes onto two.
  static const handMinVisible = 48.0;

  /// The largest width of a hand card in the draw step, where the hand is
  /// read, not played, and yields its height to the felt.
  static const handCompact = 48.0;

  /// The discard pile and the cards played, on a phone and a wide screen.
  static const tablePhone = 70.0;
  static const tableWide = 84.0;

  /// The cards played this turn on a phone while this player draws: the
  /// pile and the deck are the targets then, and the hand needs the room.
  static const tablePlayedDraw = 49.0;

  /// How far a selected card rises, and its amber edge.
  static const selectedLift = 20.0;
  static const selectedBorder = 2.0;
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
