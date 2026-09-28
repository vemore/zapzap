import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/game_state.dart';
import '../utils/app_theme.dart';
import '../utils/turn_timer.dart';

/// The time left of the turn under way, "⏱ 0:42", on the line of the player
/// to move (`GAME_RULES.md`, "Turn Time Limit"). Every player sees it, not
/// only the one on turn.
///
/// It counts down from [clock]'s figure — the server's deadline less the
/// server's time of the answer — from the moment it is first shown, with a
/// periodic timer whose `tick` counts the seconds gone by even when the app
/// was held up; the device's clock is never read. A new [clock] (a refetch,
/// the next turn) starts it again from its own figure. At 0:00 it stops: the
/// server ejects the late player and the next event redraws the table.
class TurnCountdown extends StatefulWidget {
  const TurnCountdown({super.key, required this.clock});

  final TurnClock clock;

  /// From this much left, the clock turns red.
  static const urgent = Duration(seconds: 10);

  static const countdownKey = Key('turnCountdown');

  @override
  State<TurnCountdown> createState() => _TurnCountdownState();
}

class _TurnCountdownState extends State<TurnCountdown> {
  Timer? _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(TurnCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock) _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = null;
    final atAnswer = widget.clock.left;
    _left = atAnswer;
    if (atAnswer <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = atAnswer - Duration(seconds: timer.tick);
      setState(() => _left = left.isNegative ? Duration.zero : left);
      if (_left == Duration.zero) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = turnClockText(_left);
    final color = _left <= TurnCountdown.urgent
        ? AppColors.error
        : AppColors.amber400;
    return Semantics(
      label: l10n.gameTurnTimeLeft(text),
      excludeSemantics: true,
      child: Row(
        key: TurnCountdown.countdownKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
