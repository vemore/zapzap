import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import RoundEnd from '../RoundEnd';

describe('Phase 7: RoundEnd Component Tests', () => {
  const mockRoundData = {
    players: [
      { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 15 },
      { id: '2', username: 'Bob', hand: [2, 15], handValue: 6, score: 6, totalScore: 25 },
      { id: '3', username: 'Charlie', hand: [52, 13], handValue: 26, score: 26, totalScore: 50 },
    ],
    zapZapCaller: null,
    roundNumber: 5,
  };

  describe('Basic Display', () => {
    it('should render round end title', () => {
      render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      expect(screen.getByText(/round 5 complete/i)).toBeInTheDocument();
    });

    it('should display all players', () => {
      render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
      expect(screen.getByText('Charlie')).toBeInTheDocument();
    });

    it('should show player hands', () => {
      const { container } = render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      // Should render card displays for each player
      const hands = container.querySelectorAll('.player-hand-display');
      expect(hands.length).toBe(3);
    });

    it('should display round scores', () => {
      const { container } = render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      const roundScores = container.querySelectorAll('.round-score .value');
      const scoreTexts = Array.from(roundScores).map((el) => el.textContent);

      expect(scoreTexts).toContain('0 points');
      expect(scoreTexts).toContain('6 points');
      expect(scoreTexts).toContain('26 points');
    });

    it('should display total scores', () => {
      const { container } = render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      const totalScores = container.querySelectorAll('.total-score .value');
      const scoreTexts = Array.from(totalScores).map((el) => el.textContent);

      expect(scoreTexts).toContain('15');
      expect(scoreTexts).toContain('25');
      expect(scoreTexts).toContain('50');
    });
  });

  describe('Lowest Hand Indicator', () => {
    it('should highlight player with lowest hand', () => {
      const { container } = render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      const aliceRow = screen.getByText('Alice').closest('.player-row');
      expect(aliceRow.className).toMatch(/lowest|winner/i);
    });

    it('should show 0 points for lowest hand', () => {
      render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      const aliceRow = screen.getByText('Alice').closest('.player-row');
      expect(aliceRow.textContent).toMatch(/0.*points/i);
    });
  });

  describe('ZapZap Display', () => {
    it('should show ZapZap caller when successful', () => {
      const zapZapData = {
        ...mockRoundData,
        zapZapCaller: '1', // Alice called ZapZap and won
      };

      const { container } = render(<RoundEnd roundData={zapZapData} onContinue={vi.fn()} />);

      const zapIndicator = container.querySelector('.zapzap-indicator');
      expect(zapIndicator.textContent).toMatch(/alice/i);
      expect(zapIndicator.textContent).toMatch(/successful/i);
    });

    it('should show counteract when ZapZap failed', () => {
      const counteractData = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 15 },
          { id: '2', username: 'Bob', hand: [0, 13, 26, 39], handValue: 4, score: 29, totalScore: 40 }, // Counteracted!
          { id: '3', username: 'Charlie', hand: [2, 15], handValue: 6, score: 6, totalScore: 20 },
        ],
        zapZapCaller: '2', // Bob called ZapZap but Alice had lower hand
        roundNumber: 3,
      };

      const { container } = render(<RoundEnd roundData={counteractData} onContinue={vi.fn()} />);

      const zapIndicator = container.querySelector('.zapzap-indicator');
      expect(zapIndicator.textContent).toMatch(/bob/i);
      expect(zapIndicator.textContent).toMatch(/counteract/i);
    });

    it('should show counteract penalty calculation', () => {
      const counteractData = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 15 },
          { id: '2', username: 'Bob', hand: [0, 13, 26, 39], handValue: 4, score: 29, totalScore: 40 },
        ],
        zapZapCaller: '2',
        roundNumber: 3,
      };

      render(<RoundEnd roundData={counteractData} onContinue={vi.fn()} />);

      // Should show penalty calculation: 4 + (2 × 5) = 14, but Bob actually has 29
      // The component should explain the penalty
      expect(screen.getByText(/penalty/i)).toBeInTheDocument();
    });
  });

  describe('Hand Value Display', () => {
    it('should show hand values', () => {
      render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      // Alice: 3 points
      const aliceRow = screen.getByText('Alice').closest('.player-row');
      expect(aliceRow.textContent).toMatch(/3|A.*2/i);
    });

    it('should display card names in hands', () => {
      render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      // Should show card names (implementation might vary)
      // At minimum, should show some representation of cards
      const hands = screen.getAllByText(/♠|♥|♣|♦|joker/i);
      expect(hands.length).toBeGreaterThan(0);
    });
  });

  describe('Continue Button', () => {
    it('should render continue button', () => {
      render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      expect(screen.getByRole('button', { name: /continue|next/i })).toBeInTheDocument();
    });

    it('should call onContinue when button clicked', () => {
      const onContinue = vi.fn();
      render(<RoundEnd roundData={mockRoundData} onContinue={onContinue} />);

      const continueButton = screen.getByRole('button', { name: /continue|next/i });
      fireEvent.click(continueButton);

      expect(onContinue).toHaveBeenCalled();
    });

    it('should disable continue button when disabled', () => {
      render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} disabled />);

      const continueButton = screen.getByRole('button', { name: /continue|next/i });
      expect(continueButton).toBeDisabled();
    });
  });

  describe('Eliminated Players', () => {
    it('should mark eliminated players (>100 points)', () => {
      const eliminatedData = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 95 },
          { id: '2', username: 'Bob', hand: [10, 24], handValue: 23, score: 23, totalScore: 105 }, // Eliminated!
        ],
        zapZapCaller: null,
        roundNumber: 8,
      };

      const { container } = render(<RoundEnd roundData={eliminatedData} onContinue={vi.fn()} />);

      const playerRows = container.querySelectorAll('.player-row');
      const bobRow = Array.from(playerRows).find((row) => row.textContent.includes('Bob'));
      expect(bobRow.className).toMatch(/eliminated/i);
    });

    it('should show elimination message', () => {
      const eliminatedData = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 95 },
          { id: '2', username: 'Bob', hand: [10, 24], handValue: 23, score: 23, totalScore: 105 },
        ],
        zapZapCaller: null,
        roundNumber: 8,
      };

      const { container } = render(<RoundEnd roundData={eliminatedData} onContinue={vi.fn()} />);

      const eliminationsSection = container.querySelector('.eliminations');
      expect(eliminationsSection.textContent).toMatch(/bob.*eliminated/i);
    });
  });

  describe('Sorting and Display Order', () => {
    it('should display players in score order (lowest first)', () => {
      const { container } = render(<RoundEnd roundData={mockRoundData} onContinue={vi.fn()} />);

      const playerRows = container.querySelectorAll('.player-row');
      const names = Array.from(playerRows).map((row) => row.textContent);

      // Alice (0) should be first, then Bob (6), then Charlie (26)
      expect(names[0]).toMatch(/alice/i);
      expect(names[1]).toMatch(/bob/i);
      expect(names[2]).toMatch(/charlie/i);
    });
  });

  describe('Loading State', () => {
    it('should handle null roundData', () => {
      const { container } = render(<RoundEnd roundData={null} onContinue={vi.fn()} />);

      expect(container.textContent).toMatch(/loading|calculating/i);
    });

    it('should handle empty players array', () => {
      const emptyData = { ...mockRoundData, players: [] };
      const { container } = render(<RoundEnd roundData={emptyData} onContinue={vi.fn()} />);

      expect(container.textContent).toMatch(/no players|error/i);
    });
  });
});
