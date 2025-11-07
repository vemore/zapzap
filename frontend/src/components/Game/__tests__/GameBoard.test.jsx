import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import GameBoard from '../GameBoard';

describe('Phase 5: GameBoard Component Tests', () => {
  const mockGameState = {
    partyId: 'party1',
    players: [
      { id: '1', username: 'Alice', cardCount: 5, score: 0 },
      { id: '2', username: 'Bob', cardCount: 7, score: 10 },
    ],
    currentTurnId: '1',
    currentAction: 'play',
    myHand: [0, 14, 28], // A♠ 2♥ 3♣
    myUserId: '1',
  };

  describe('Component Integration', () => {
    it('should render all sub-components', () => {
      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // Should render PlayerTable
      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();

      // Should render PlayerHand
      expect(screen.getByText(/3 cards/i)).toBeInTheDocument();

      // Should render ActionButtons
      expect(screen.getByRole('button', { name: /play/i })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /draw/i })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /zapzap/i })).toBeInTheDocument();
    });

    it('should pass correct props to PlayerTable', () => {
      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // Check that current turn player is highlighted
      const aliceCard = screen.getByText('Alice').closest('.player-card');
      expect(aliceCard.className).toMatch(/current-turn/i);
    });

    it('should pass correct props to PlayerHand', () => {
      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // Hand should display correct card count
      const handInfo = screen.getByText(/3 cards/i);
      expect(handInfo).toBeInTheDocument();
    });

    it('should pass correct props to ActionButtons', () => {
      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // Should show "Your Turn" since currentTurnId === myUserId
      expect(screen.getByText(/your turn/i)).toBeInTheDocument();
    });
  });

  describe('Card Selection Flow', () => {
    it('should update selected cards when cards are clicked', () => {
      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      const cards = screen.getAllByRole('button').filter((btn) =>
        btn.className.includes('card')
      );

      fireEvent.click(cards[0]);

      // Play button should now show (1) selected card
      const playButton = screen.getByRole('button', { name: /play.*1/i });
      expect(playButton).toBeInTheDocument();
    });

    it('should validate selected cards before enabling play', () => {
      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      const cards = screen.getAllByRole('button').filter((btn) =>
        btn.className.includes('card')
      );

      // Select a single card (always valid)
      fireEvent.click(cards[0]);

      const playButton = screen.getByRole('button', { name: /play/i });
      expect(playButton).not.toBeDisabled();
    });
  });

  describe('Action Handlers', () => {
    it('should call onPlay with selected cards', () => {
      const onPlay = vi.fn();
      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={onPlay}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      const cards = screen.getAllByRole('button').filter((btn) =>
        btn.className.includes('card')
      );

      fireEvent.click(cards[0]);

      const playButton = screen.getByRole('button', { name: /play/i });
      fireEvent.click(playButton);

      expect(onPlay).toHaveBeenCalledWith([0]);
    });

    it('should call onDraw when draw button clicked', () => {
      const onDraw = vi.fn();
      const drawState = { ...mockGameState, currentAction: 'draw' };

      render(
        <GameBoard
          gameState={drawState}
          onPlay={vi.fn()}
          onDraw={onDraw}
          onZapZap={vi.fn()}
        />
      );

      const drawButton = screen.getByRole('button', { name: /draw/i });
      fireEvent.click(drawButton);

      expect(onDraw).toHaveBeenCalled();
    });

    it('should call onZapZap when zapzap button clicked', () => {
      const onZapZap = vi.fn();
      const zapEligibleState = {
        ...mockGameState,
        myHand: [0, 14], // A♠ 2♥ = 3 points (eligible)
      };

      render(
        <GameBoard
          gameState={zapEligibleState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={onZapZap}
        />
      );

      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      fireEvent.click(zapButton);

      expect(onZapZap).toHaveBeenCalled();
    });
  });

  describe('Turn State Management', () => {
    it('should disable actions when not my turn', () => {
      const notMyTurnState = { ...mockGameState, currentTurnId: '2' };

      render(
        <GameBoard
          gameState={notMyTurnState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      const playButton = screen.getByRole('button', { name: /play/i });
      const drawButton = screen.getByRole('button', { name: /draw/i });
      const zapButton = screen.getByRole('button', { name: /zapzap/i });

      expect(playButton).toBeDisabled();
      expect(drawButton).toBeDisabled();
      expect(zapButton).toBeDisabled();
    });

    it('should show waiting message when not my turn', () => {
      const notMyTurnState = { ...mockGameState, currentTurnId: '2' };

      render(
        <GameBoard
          gameState={notMyTurnState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      expect(screen.getByText(/waiting/i)).toBeInTheDocument();
    });
  });

  describe('ZapZap Eligibility', () => {
    it('should enable zapzap when hand ≤5 points', () => {
      const zapEligibleState = {
        ...mockGameState,
        myHand: [0, 13, 26, 39], // Four Aces = 4 points
      };

      render(
        <GameBoard
          gameState={zapEligibleState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      expect(zapButton).not.toBeDisabled();
    });

    it('should disable zapzap when hand >5 points', () => {
      const notEligibleState = {
        ...mockGameState,
        myHand: [2, 15], // 3♠ 3♥ = 6 points
      };

      render(
        <GameBoard
          gameState={notEligibleState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      expect(zapButton).toBeDisabled();
    });
  });

  describe('Loading and Error States', () => {
    it('should show loading when no game state', () => {
      render(
        <GameBoard
          gameState={null}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      expect(screen.getByText(/loading/i)).toBeInTheDocument();
    });

    it('should handle missing hand gracefully', () => {
      const noHandState = { ...mockGameState, myHand: [] };

      render(
        <GameBoard
          gameState={noHandState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      expect(screen.getByText(/no cards/i)).toBeInTheDocument();
    });
  });
});
