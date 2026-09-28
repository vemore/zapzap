import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import TurnTimer from '../TurnTimer';
import { turnClockOf, secondsLeft, monotonicNow } from '../../../hooks/useTurnCountdown';

// The countdown of the turn clock: `turnDeadline − serverTime` from the response, minus
// the time elapsed here since it arrived. vitest's fake timers move performance.now()
// and Date.now() alike.

describe('TurnTimer', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('counts down every second from the server deadline, then stops at 0:00', () => {
    // A server clock far from the browser's changes nothing
    const clock = turnClockOf(
      { turnTimeLimit: 30, turnDeadline: 5_000_030_000, serverTime: 5_000_000_000 },
      monotonicNow()
    );

    render(<TurnTimer clock={clock} />);
    expect(screen.getByRole('timer')).toHaveTextContent('0:30');

    act(() => vi.advanceTimersByTime(5000));
    expect(screen.getByRole('timer')).toHaveTextContent('0:25');

    act(() => vi.advanceTimersByTime(40_000));
    expect(screen.getByRole('timer')).toHaveTextContent('0:00');
  });

  it('turns red for the last ten seconds', () => {
    const clock = turnClockOf(
      { turnTimeLimit: 30, turnDeadline: 11_000, serverTime: 0 },
      monotonicNow()
    );

    render(<TurnTimer clock={clock} />);
    expect(screen.getByRole('timer').className).not.toMatch(/text-red/);

    act(() => vi.advanceTimersByTime(1000));
    expect(screen.getByRole('timer')).toHaveTextContent('0:10');
    expect(screen.getByRole('timer').className).toMatch(/text-red/);
  });

  it('writes two minutes as 2:00', () => {
    const clock = turnClockOf({ turnTimeLimit: 120, turnDeadline: 120_000, serverTime: 0 }, monotonicNow());

    render(<TurnTimer clock={clock} />);

    expect(screen.getByRole('timer')).toHaveTextContent('2:00');
  });

  it('renders nothing without a clock', () => {
    const { container } = render(<TurnTimer clock={null} />);

    expect(container).toBeEmptyDOMElement();
  });
});

describe('turnClockOf', () => {
  it('is null when the game runs no clock or the seat on turn is not timed', () => {
    expect(turnClockOf({ turnTimeLimit: 0, turnDeadline: null, serverTime: 1 }, 0)).toBeNull();
    expect(turnClockOf({ turnTimeLimit: 30, turnDeadline: null, serverTime: 1 }, 0)).toBeNull();
    expect(turnClockOf({ turnTimeLimit: 30, turnDeadline: 5 }, 0)).toBeNull();
    expect(turnClockOf({}, 0)).toBeNull();
  });

  it('counts from the response, never from the browser clock', () => {
    const clock = turnClockOf({ turnTimeLimit: 60, turnDeadline: 90_500, serverTime: 50_000 }, 1000);

    expect(clock).toEqual({ limitSeconds: 60, remainingMs: 40_500, receivedAt: 1000 });
    expect(secondsLeft(clock, 1000)).toBe(41);
    expect(secondsLeft(clock, 11_000)).toBe(31);
    expect(secondsLeft(clock, 100_000)).toBe(0);
  });
});
