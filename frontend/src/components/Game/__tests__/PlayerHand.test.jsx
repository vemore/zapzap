import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import PlayerHand from '../PlayerHand';

describe('Phase 5: PlayerHand Component Tests', () => {
  describe('Card Display', () => {
    it('should render all cards in hand', () => {
      const hand = [0, 14, 28]; // A♠ 2♥ 3♣
      render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} />);

      // Should show 3 cards
      const cards = screen.getAllByRole('button');
      expect(cards.length).toBeGreaterThanOrEqual(3);
    });

    it('should render empty hand', () => {
      const { container } = render(<PlayerHand hand={[]} onCardsSelected={vi.fn()} />);
      expect(container.textContent).toMatch(/no cards|empty/i);
    });

    it('should display card count', () => {
      const hand = [0, 14, 28, 42, 52];
      render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} />);

      expect(screen.getByText(/5 cards?/i)).toBeInTheDocument();
    });
  });

  describe('Card Selection', () => {
    it('should allow selecting cards', () => {
      const hand = [0, 14, 28];
      const onCardsSelected = vi.fn();
      render(<PlayerHand hand={hand} onCardsSelected={onCardsSelected} />);

      const cards = screen.getAllByRole('button');
      fireEvent.click(cards[0]);

      expect(onCardsSelected).toHaveBeenCalledWith([0]);
    });

    it('should allow selecting multiple cards', () => {
      const hand = [0, 14, 28];
      const onCardsSelected = vi.fn();
      render(<PlayerHand hand={hand} onCardsSelected={onCardsSelected} />);

      const cards = screen.getAllByRole('button');
      fireEvent.click(cards[0]);
      fireEvent.click(cards[1]);

      expect(onCardsSelected).toHaveBeenLastCalledWith([0, 14]);
    });

    it('should allow deselecting cards', () => {
      const hand = [0, 14, 28];
      const onCardsSelected = vi.fn();
      render(<PlayerHand hand={hand} onCardsSelected={onCardsSelected} />);

      const cards = screen.getAllByRole('button');
      fireEvent.click(cards[0]); // Select
      fireEvent.click(cards[0]); // Deselect

      expect(onCardsSelected).toHaveBeenLastCalledWith([]);
    });

    it('should clear selection on clear button', () => {
      const hand = [0, 14, 28];
      const onCardsSelected = vi.fn();
      render(<PlayerHand hand={hand} onCardsSelected={onCardsSelected} />);

      const cards = screen.getAllByRole('button');
      fireEvent.click(cards[0]);

      const clearButton = screen.getByRole('button', { name: /clear/i });
      fireEvent.click(clearButton);

      expect(onCardsSelected).toHaveBeenLastCalledWith([]);
    });
  });

  describe('Hand Value Display', () => {
    it('should show eligibility value (Joker=0)', () => {
      const hand = [52, 41, 1]; // Joker 3♦ 2♠ = 0+3+2 = 5
      render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} />);

      expect(screen.getByText(/eligibility.*5/i)).toBeInTheDocument();
    });

    it('should show penalty value (Joker=25)', () => {
      const hand = [52, 41, 1]; // Joker 3♦ 2♠ = 25+3+2 = 30
      render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} />);

      expect(screen.getByText(/penalty.*30/i)).toBeInTheDocument();
    });

    it('should highlight ZapZap eligibility when ≤5', () => {
      const hand = [0, 14, 27]; // A♠ 2♥ 2♣ = 5
      render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} />);

      expect(screen.getByText(/zapzap eligible/i)).toBeInTheDocument();
    });

    it('should NOT highlight when >5 points', () => {
      const hand = [2, 15]; // 3♠ 3♥ = 6
      render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} />);

      expect(screen.queryByText(/zapzap eligible/i)).not.toBeInTheDocument();
    });
  });

  describe('Disabled State', () => {
    it('should disable card selection when disabled', () => {
      const hand = [0, 14, 28];
      const onCardsSelected = vi.fn();
      render(<PlayerHand hand={hand} onCardsSelected={onCardsSelected} disabled />);

      const cards = screen.getAllByRole('button');
      fireEvent.click(cards[0]);

      expect(onCardsSelected).not.toHaveBeenCalled();
    });

    it('should disable clear button when disabled', () => {
      const hand = [0, 14, 28];
      render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} disabled />);

      const clearButton = screen.getByRole('button', { name: /clear/i });
      expect(clearButton).toBeDisabled();
    });
  });

  describe('Selected Cards Highlight', () => {
    it('should visually highlight selected cards', () => {
      const hand = [0, 14, 28];
      const { container } = render(<PlayerHand hand={hand} onCardsSelected={vi.fn()} />);

      const cards = screen.getAllByRole('button');
      fireEvent.click(cards[0]);

      // Check for selected class or style
      const selectedCard = cards[0];
      expect(selectedCard.className).toMatch(/selected|active|highlight/i);
    });
  });
});
