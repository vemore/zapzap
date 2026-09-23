import 'package:intl/intl.dart';

/// The formats the history and statistics screens share.
///
/// Dates come out of the models as UTC [DateTime] (the backends send Unix
/// seconds, `models/json.dart`) and are shown in the device's zone, in the
/// app's locale — the React client hard-codes `fr-FR`
/// (`frontend/src/components/History/GameHistory.jsx:36`).
abstract final class Formats {
  /// Shown when a value is missing (a Rust history entry has no winner
  /// score, a game that never finished has no date).
  static const missing = '—';

  /// Date and time of [value] in [locale], the clock as the locale writes
  /// it: `22/09/2026 14:26` in French, `9/22/2026 2:26 PM` in English.
  static String dateTime(DateTime? value, String locale) => value == null
      ? missing
      : DateFormat.yMd(locale).add_jm().format(value.toLocal());

  /// A 0..1 rate as a percentage with one decimal, as React's
  /// `formatPercentage` (`frontend/src/components/Stats/Statistics.jsx:61`).
  static String percent(double? value) =>
      '${((value ?? 0) * 100).toStringAsFixed(1)}%';

  /// A score or average with one decimal.
  static String decimal(double? value) => (value ?? 0).toStringAsFixed(1);
}
