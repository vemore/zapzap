import { useEffect, useState } from 'react';

// The turn clock of GET /game/:id/state (GAME_RULES.md, Turn Time Limit): the deadline
// is the server's, in Unix ms. The browser's clock may be off by any amount, so the time
// left is `turnDeadline − serverTime` as the response said it, minus the time elapsed
// here since the response arrived (performance.now(), which no clock change moves).

/** Local monotonic time in ms */
export const monotonicNow = () => performance.now();

/**
 * The turn clock of a game state: `{ limitSeconds, remainingMs, receivedAt }`, or null
 * when the seat on turn is not timed (no limit, a bot's turn, between two rounds).
 *
 * @param {Object} gameState - `gameState` of the state response
 * @param {number} receivedAt - monotonicNow() when the response arrived
 */
export function turnClockOf(gameState, receivedAt) {
  const { turnTimeLimit, turnDeadline, serverTime } = gameState || {};
  if (!turnTimeLimit || turnDeadline == null || serverTime == null) return null;
  return {
    limitSeconds: turnTimeLimit,
    remainingMs: turnDeadline - serverTime,
    receivedAt,
  };
}

/** Whole seconds left on a turn clock at `now` (0 once it has run out) */
export function secondsLeft(clock, now = monotonicNow()) {
  const ms = clock.remainingMs - (now - clock.receivedAt);
  return Math.max(0, Math.ceil(ms / 1000));
}

/**
 * The seconds left on `clock`, ticking; null without a clock.
 *
 * @param {Object|null} clock - from turnClockOf
 * @param {number} tickMs - how often it is recomputed
 */
export default function useTurnCountdown(clock, tickMs = 250) {
  const [seconds, setSeconds] = useState(() => (clock ? secondsLeft(clock) : null));

  useEffect(() => {
    if (!clock) {
      setSeconds(null);
      return undefined;
    }
    const update = () => setSeconds(secondsLeft(clock));
    update();
    const id = setInterval(update, tickMs);
    return () => clearInterval(id);
  }, [clock, tickMs]);

  return seconds;
}
