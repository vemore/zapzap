import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import RoundEnd from '../RoundEnd';

const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// RoundEnd navigates home once the game is over, so it renders inside a router
const renderRoundEnd = (props) =>
  render(
    <MemoryRouter>
      <RoundEnd {...props} />
    </MemoryRouter>
  );

// Each player is a bordered card: name and badges, hand, "This Round" and "Total Score"
const cardOf = (name) => screen.getByText(name, { selector: 'span' }).closest('.p-5');
const cardNames = (container) =>
  Array.from(container.querySelectorAll('.p-5')).map(
    (card) => card.querySelector('span.text-lg').textContent
  );
const roundScoreOf = (name) =>
  cardOf(name).querySelector('p.text-xl').textContent; // first box: This Round
const totalScoreOf = (name) =>
  cardOf(name).querySelectorAll('p.text-xl')[1].textContent; // second box: Total Score

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
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      expect(screen.getByText(/round 5 complete/i)).toBeInTheDocument();
    });

    it('should display all players', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
      expect(screen.getByText('Charlie')).toBeInTheDocument();
    });

    it('should show player hands', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      // Two cards per player, each hand under its own player
      expect(cardOf('Alice').querySelectorAll('[role="button"]')).toHaveLength(2);
      expect(cardOf('Bob').querySelectorAll('[role="button"]')).toHaveLength(2);
      expect(cardOf('Charlie').querySelectorAll('[role="button"]')).toHaveLength(2);
    });

    it('should display round scores', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      expect(roundScoreOf('Alice')).toBe('0 pts');
      expect(roundScoreOf('Bob')).toBe('6 pts');
      expect(roundScoreOf('Charlie')).toBe('26 pts');
    });

    it('should display total scores', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      expect(totalScoreOf('Alice')).toBe('15');
      expect(totalScoreOf('Bob')).toBe('25');
      expect(totalScoreOf('Charlie')).toBe('50');
    });
  });

  describe('Lowest Hand Indicator', () => {
    it('should highlight player with lowest hand', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      expect(cardOf('Alice')).toHaveTextContent(/lowest hand/i);
      expect(cardOf('Alice').className).toMatch(/border-amber-400/);
      expect(cardOf('Bob')).not.toHaveTextContent(/lowest hand/i);
      expect(screen.getAllByText(/lowest hand/i)).toHaveLength(1);
    });

    it('should show 0 points for lowest hand', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      expect(roundScoreOf('Alice')).toBe('0 pts');
    });
  });

  describe('ZapZap Display', () => {
    it('should show ZapZap caller when successful', () => {
      const zapZapData = {
        ...mockRoundData,
        zapZapCaller: '1', // Alice called ZapZap and won
      };

      renderRoundEnd({ roundData: zapZapData, onContinue: vi.fn() });

      const zapIndicator = screen.getByText(/successfully called/i).closest('p');
      expect(zapIndicator).toHaveTextContent(/alice/i);
      expect(zapIndicator).toHaveTextContent(/successfully called zapzap/i);
      expect(screen.queryByText(/counteracted/i)).not.toBeInTheDocument();
    });

    it('should show counteract when ZapZap failed', () => {
      const counteractData = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 15 },
          { id: '2', username: 'Bob', hand: [0, 13, 26, 39], handValue: 4, score: 14, totalScore: 40 }, // Counteracted!
          { id: '3', username: 'Charlie', hand: [2, 15], handValue: 6, score: 6, totalScore: 20 },
        ],
        zapZapCaller: '2', // Bob called ZapZap but Alice had lower hand
        wasCounterActed: true,
        roundNumber: 3,
      };

      renderRoundEnd({ roundData: counteractData, onContinue: vi.fn() });

      const zapIndicator = screen.getByText(/called zapzap but was/i).closest('p');
      expect(zapIndicator).toHaveTextContent(/bob/i);
      expect(zapIndicator).toHaveTextContent(/counteracted/i);
      expect(screen.queryByText(/successfully called/i)).not.toBeInTheDocument();
    });

    it('should show counteract penalty calculation', () => {
      const counteractData = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 15 },
          { id: '2', username: 'Bob', hand: [0, 13, 26, 39], handValue: 4, score: 9, totalScore: 40 },
        ],
        zapZapCaller: '2',
        wasCounterActed: true,
        roundNumber: 3,
      };

      renderRoundEnd({ roundData: counteractData, onContinue: vi.fn() });

      // Penalty = hand + ((active players − 1) × 5) = 4 + (1 × 5) = 9 (GAME_RULES.md)
      expect(screen.getByText(/penalty/i)).toHaveTextContent('Penalty: 4 + (1 × 5) = 9 points');
    });
  });

  describe('Hand Value Display', () => {
    it('should show hand values', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      // Alice holds A♠ 2♥ (3 points): both cards are under her name
      expect(cardOf('Alice').querySelector('[aria-label="Card As"]')).not.toBeNull();
      expect(cardOf('Alice').querySelector('[aria-label="Card 2h"]')).not.toBeNull();
    });

    it('should display card names in hands', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      // Standard cards are named by their cardmeister id, jokers by colour
      expect(screen.getByRole('button', { name: 'Card As' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Joker red' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Card Ah' })).toBeInTheDocument();
    });
  });

  describe('Continue Button', () => {
    it('should render continue button', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn() });

      expect(screen.getByRole('button', { name: /continue|next/i })).toBeInTheDocument();
    });

    it('should call onContinue when button clicked', () => {
      const onContinue = vi.fn();
      renderRoundEnd({ roundData: mockRoundData, onContinue });

      const continueButton = screen.getByRole('button', { name: /continue|next/i });
      fireEvent.click(continueButton);

      expect(onContinue).toHaveBeenCalled();
    });

    it('should disable continue button when disabled', () => {
      renderRoundEnd({ roundData: mockRoundData, onContinue: vi.fn(), disabled: true });

      const continueButton = screen.getByRole('button', { name: /continue|next/i });
      expect(continueButton).toBeDisabled();
    });

    it('should offer the way back to the parties once the game is over', () => {
      const finishedData = {
        ...mockRoundData,
        gameFinished: true,
        winner: { username: 'Alice', score: 15 },
      };
      const onContinue = vi.fn();
      renderRoundEnd({ roundData: finishedData, onContinue });

      expect(screen.getByText(/game over/i)).toBeInTheDocument();
      expect(screen.getByText('WINNER')).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /continue/i })).not.toBeInTheDocument();

      fireEvent.click(screen.getByRole('button', { name: /back to parties/i }));
      expect(mockNavigate).toHaveBeenCalledWith('/parties');
      expect(onContinue).not.toHaveBeenCalled();
    });
  });

  describe('Eliminated Players', () => {
    const eliminatedData = {
      players: [
        { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 95 },
        { id: '2', username: 'Bob', hand: [10, 24], handValue: 23, score: 23, totalScore: 105 }, // Eliminated!
      ],
      zapZapCaller: null,
      roundNumber: 8,
    };

    it('should mark eliminated players (>100 points)', () => {
      renderRoundEnd({ roundData: eliminatedData, onContinue: vi.fn() });

      expect(cardOf('Bob')).toHaveTextContent('Eliminated');
      expect(cardOf('Bob').className).toMatch(/border-red-500/);
      expect(cardOf('Alice')).not.toHaveTextContent('Eliminated');
    });

    it('should show elimination message', () => {
      renderRoundEnd({ roundData: eliminatedData, onContinue: vi.fn() });

      const eliminationsSection = screen.getByText('Eliminated Players').closest('.p-6');
      expect(eliminationsSection).toHaveTextContent(/bob eliminated with 105 points/i);
      expect(eliminationsSection).not.toHaveTextContent(/alice/i);
    });
  });

  describe('Sorting and Display Order', () => {
    it('should display players in score order (lowest first)', () => {
      const { container } = renderRoundEnd({
        roundData: {
          ...mockRoundData,
          players: [mockRoundData.players[2], mockRoundData.players[0], mockRoundData.players[1]],
        },
        onContinue: vi.fn(),
      });

      // Alice (0) should be first, then Bob (6), then Charlie (26)
      expect(cardNames(container)).toEqual(['Alice', 'Bob', 'Charlie']);
    });
  });

  describe('Loading State', () => {
    it('should handle null roundData', () => {
      const { container } = renderRoundEnd({ roundData: null, onContinue: vi.fn() });

      expect(container.textContent).toMatch(/loading|calculating/i);
    });

    it('should handle empty players array', () => {
      const emptyData = { ...mockRoundData, players: [] };
      const { container } = renderRoundEnd({ roundData: emptyData, onContinue: vi.fn() });

      expect(container.textContent).toMatch(/no players|error/i);
    });
  });
});
