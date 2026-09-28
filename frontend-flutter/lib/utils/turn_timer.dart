import '../l10n/app_localizations.dart';

/// The texts of the turn time limit (`GAME_RULES.md`, "Turn Time Limit"),
/// kept beside the l10n so the models stay free of Flutter.
extension TurnTimerL10n on AppLocalizations {
  /// A limit of [seconds] per turn as the form and the lobby name it: "Sans
  /// limite", "30 s", "1 min", "2 min".
  String turnTimeLimitText(int seconds) {
    if (seconds <= 0) return turnTimerOff;
    if (seconds % 60 == 0) return turnTimerMinutes(seconds ~/ 60);
    return turnTimerSeconds(seconds);
  }
}

/// [left] as a clock reads, "1:05", "0:09": whole seconds, rounded up, so
/// the clock shows 0:00 only once the time is gone.
String turnClockText(Duration left) {
  final ms = left.inMilliseconds;
  final seconds = ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
