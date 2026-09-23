import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import ActionButtons from '../ActionButtons';

describe('Phase 5: ActionButtons Component Tests', () => {
  describe('Play Button', () => {
    it('should render play button', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
        />
      );

      expect(screen.getByRole('button', { name: /play/i })).toBeInTheDocument();
    });

    it('should disable play button when no cards selected', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
        />
      );

      const playButton = screen.getByRole('button', { name: /play/i });
      expect(playButton).toBeDisabled();
    });

    it('should enable play button when cards selected', () => {
      render(
        <ActionButtons
          selectedCards={[0, 14, 28]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
        />
      );

      const playButton = screen.getByRole('button', { name: /play/i });
      expect(playButton).not.toBeDisabled();
    });

    it('should call onPlay when clicked', () => {
      const onPlay = vi.fn();
      render(
        <ActionButtons
          selectedCards={[0, 14, 28]}
          onPlay={onPlay}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
        />
      );

      const playButton = screen.getByRole('button', { name: /play/i });
      fireEvent.click(playButton);

      expect(onPlay).toHaveBeenCalledWith([0, 14, 28]);
    });

    it('should disable play button when not player turn', () => {
      render(
        <ActionButtons
          selectedCards={[0, 14, 28]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={false}
        />
      );

      const playButton = screen.getByRole('button', { name: /play/i });
      expect(playButton).toBeDisabled();
    });

    it('should show invalid play warning', () => {
      render(
        <ActionButtons
          selectedCards={[0, 25]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
          invalidPlay="Mixed ranks"
        />
      );

      expect(screen.getByRole('alert')).toHaveTextContent(/mixed ranks/i);
      expect(screen.getByRole('button', { name: /play/i })).toBeDisabled();
    });
  });

  describe('Draw Button', () => {
    it('should render draw button', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="draw"
          isMyTurn={true}
        />
      );

      expect(screen.getByRole('button', { name: /draw/i })).toBeInTheDocument();
    });

    it('should enable draw button when action is draw', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="draw"
          isMyTurn={true}
        />
      );

      const drawButton = screen.getByRole('button', { name: /draw/i });
      expect(drawButton).not.toBeDisabled();
    });

    it('should disable draw button when action is not draw', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
        />
      );

      const drawButton = screen.getByRole('button', { name: /draw/i });
      expect(drawButton).toBeDisabled();
    });

    it('should call onDrawFromDeck when clicked', () => {
      const onDrawFromDeck = vi.fn();
      const onDrawFromDiscard = vi.fn();
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={onDrawFromDeck}
          onDrawFromDiscard={onDrawFromDiscard}
          onZapZap={vi.fn()}
          currentAction="draw"
          isMyTurn={true}
        />
      );

      const drawButton = screen.getByRole('button', { name: /draw/i });
      fireEvent.click(drawButton);

      expect(onDrawFromDeck).toHaveBeenCalled();
      expect(onDrawFromDiscard).not.toHaveBeenCalled();
    });

    it('should take the selected discard card instead of drawing from the deck', () => {
      const onDrawFromDeck = vi.fn();
      const onDrawFromDiscard = vi.fn();
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={onDrawFromDeck}
          onDrawFromDiscard={onDrawFromDiscard}
          onZapZap={vi.fn()}
          currentAction="draw"
          isMyTurn={true}
          hasDiscardSelection={true}
          hasDiscardCards={true}
        />
      );

      fireEvent.click(screen.getByRole('button', { name: /take/i }));

      expect(onDrawFromDiscard).toHaveBeenCalled();
      expect(onDrawFromDeck).not.toHaveBeenCalled();
    });
  });

  describe('ZapZap Button', () => {
    it('should render zapzap button', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
          zapZapEligible={false}
        />
      );

      expect(screen.getByRole('button', { name: /zapzap/i })).toBeInTheDocument();
    });

    it('should disable zapzap when not eligible', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
          zapZapEligible={false}
        />
      );

      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      expect(zapButton).toBeDisabled();
    });

    it('should enable zapzap when eligible and player turn', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
          zapZapEligible={true}
        />
      );

      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      expect(zapButton).not.toBeDisabled();
    });

    it('should call onZapZap when clicked', () => {
      const onZapZap = vi.fn();
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={onZapZap}
          currentAction="play"
          isMyTurn={true}
          zapZapEligible={true}
        />
      );

      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      fireEvent.click(zapButton);

      expect(onZapZap).toHaveBeenCalled();
    });

    it('should highlight zapzap button when eligible', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
          zapZapEligible={true}
        />
      );

      // Eligible: the button pulses in amber; not eligible: plain slate
      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      expect(zapButton.className).toMatch(/animate-pulse/);
      expect(zapButton.className).toMatch(/bg-amber-400/);
    });

    it('should not highlight zapzap button when not eligible', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
          zapZapEligible={false}
        />
      );

      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      expect(zapButton.className).not.toMatch(/animate-pulse/);
    });
  });

  describe('Turn Indicator', () => {
    it('should show "Your Turn" when isMyTurn', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={true}
        />
      );

      expect(screen.getByText(/your turn/i)).toBeInTheDocument();
    });

    it('should show "Waiting" when not isMyTurn', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="play"
          isMyTurn={false}
        />
      );

      expect(screen.getByText(/waiting for other players/i)).toBeInTheDocument();
      expect(screen.queryByText(/your turn/i)).not.toBeInTheDocument();
    });

    it('should show current action', () => {
      render(
        <ActionButtons
          selectedCards={[]}
          onPlay={vi.fn()}
          onDrawFromDeck={vi.fn()}
          onZapZap={vi.fn()}
          currentAction="draw"
          isMyTurn={true}
        />
      );

      expect(screen.getByText(/your turn - draw a card/i)).toBeInTheDocument();
    });
  });
});
