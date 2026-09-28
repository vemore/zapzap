import { Timer } from 'lucide-react';
import useTurnCountdown from '../../hooks/useTurnCountdown';

/** Under this many seconds the countdown turns red */
const HURRY_SECONDS = 10;

const format = (seconds) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

/**
 * TurnTimer - the time left on the current turn, from the server's deadline
 * (useTurnCountdown). Nothing without a clock.
 *
 * @param {Object|null} clock - turnClockOf(gameState, receivedAt)
 * @param {boolean} large - the size of a screen's heading rather than of a player row
 * @param {string} className - extra classes for the badge (margins)
 */
function TurnTimer({ clock, large = false, className = '' }) {
  const seconds = useTurnCountdown(clock);
  if (seconds === null) return null;

  const hurry = seconds <= HURRY_SECONDS;
  return (
    <span
      role="timer"
      aria-label={`Time left for this turn: ${seconds} seconds`}
      data-testid="turn-timer"
      className={`inline-flex items-center gap-1 rounded-full border font-semibold tabular-nums flex-shrink-0 ${
        large ? 'px-3 py-1 text-sm' : 'px-1.5 py-0 text-[10px] sm:text-xs'
      } ${
        hurry
          ? 'bg-red-500/20 border-red-500/50 text-red-400 animate-pulse'
          : 'bg-green-500/10 border-green-400/40 text-green-300'
      } ${className}`}
    >
      <Timer className={large ? 'w-4 h-4' : 'w-3 h-3'} aria-hidden="true" />
      {format(seconds)}
    </span>
  );
}

export default TurnTimer;
