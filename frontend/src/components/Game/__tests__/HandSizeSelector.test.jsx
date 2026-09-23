import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import HandSizeSelector from '../HandSizeSelector';

// GAME_RULES.md, Round Start: the starting player chooses the hand size,
// 4-7 cards, or 4-10 in Golden Score.
const sizeButtons = () =>
  screen.getAllByRole('button').filter((b) => /^\d+$/.test(b.textContent.trim()));

describe('HandSizeSelector Component Tests', () => {
  describe('Hand Size Range (game rule)', () => {
    it('should offer 4 to 7 cards in a normal round', () => {
      render(<HandSizeSelector isMyTurn={true} onSelectHandSize={vi.fn()} />);

      expect(sizeButtons().map((b) => b.textContent.trim())).toEqual(['4', '5', '6', '7']);
    });

    it('should offer 4 to 10 cards in Golden Score', () => {
      render(<HandSizeSelector isMyTurn={true} isGoldenScore={true} onSelectHandSize={vi.fn()} />);

      expect(sizeButtons().map((b) => b.textContent.trim())).toEqual(
        ['4', '5', '6', '7', '8', '9', '10']
      );
    });
  });

  describe('Selection', () => {
    it('should send the chosen hand size on confirm', async () => {
      const onSelectHandSize = vi.fn().mockResolvedValue(undefined);
      render(<HandSizeSelector isMyTurn={true} onSelectHandSize={onSelectHandSize} />);

      fireEvent.click(screen.getByRole('button', { name: '6' }));
      fireEvent.click(screen.getByRole('button', { name: /confirm/i }));

      await waitFor(() => {
        expect(onSelectHandSize).toHaveBeenCalledWith(6);
      });
    });

    it('should not send anything when disabled', () => {
      const onSelectHandSize = vi.fn();
      render(<HandSizeSelector isMyTurn={true} disabled={true} onSelectHandSize={onSelectHandSize} />);

      const confirm = screen.getByRole('button', { name: /confirm/i });
      expect(confirm).toBeDisabled();
      fireEvent.click(confirm);
      expect(onSelectHandSize).not.toHaveBeenCalled();
    });
  });

  describe('Waiting State', () => {
    it('should name the player who is choosing when it is not my turn', () => {
      render(
        <HandSizeSelector isMyTurn={false} currentPlayerName="Bob" onSelectHandSize={vi.fn()} />
      );

      expect(screen.getByText('Bob')).toBeInTheDocument();
      expect(screen.getByText(/is selecting the number of cards/i)).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /confirm/i })).not.toBeInTheDocument();
    });
  });
});
