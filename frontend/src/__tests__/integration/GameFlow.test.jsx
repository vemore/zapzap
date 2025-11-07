import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import GameBoard from '../../components/Game/GameBoard';
import RoundEnd from '../../components/Game/RoundEnd';

describe('Phase 8: Game Flow Integration Tests', () => {
  describe('Complete Game Round Flow', () => {
    it('should complete a full round from play to scoring', async () => {
      const mockGameState = {
        partyId: 'party1',
        players: [
          { id: '1', username: 'Alice', cardCount: 3, score: 0 },
          { id: '2', username: 'Bob', cardCount: 5, score: 0 },
        ],
        currentTurnId: '1',
        currentAction: 'play',
        myHand: [0, 14, 28], // A♠ 2♥ 3♣ = 6 points
        myUserId: '1',
      };

      const onPlay = vi.fn();
      const onDraw = vi.fn();
      const onZapZap = vi.fn();

      render(
        <GameBoard
          gameState={mockGameState}
          onPlay={onPlay}
          onDraw={onDraw}
          onZapZap={onZapZap}
        />
      );

      // Player sees their hand
      expect(screen.getAllByText(/3.*cards/i).length).toBeGreaterThan(0);

      // Player can see it's their turn
      expect(screen.getByText(/your turn/i)).toBeInTheDocument();

      // Player selects a card
      const cards = screen.getAllByRole('button').filter((btn) =>
        btn.className.includes('card')
      );
      fireEvent.click(cards[0]);

      // Play button becomes enabled
      const playButton = screen.getByRole('button', { name: /play/i });
      expect(playButton).not.toBeDisabled();

      // Player plays the card
      fireEvent.click(playButton);

      // Verify play action was called
      expect(onPlay).toHaveBeenCalled();
    });

    it('should handle ZapZap eligibility correctly', () => {
      const eligibleGameState = {
        partyId: 'party1',
        players: [
          { id: '1', username: 'Alice', cardCount: 4, score: 0 },
        ],
        currentTurnId: '1',
        currentAction: 'play',
        myHand: [0, 13, 26, 39], // Four Aces = 4 points (eligible!)
        myUserId: '1',
      };

      const onZapZap = vi.fn();

      render(
        <GameBoard
          gameState={eligibleGameState}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={onZapZap}
        />
      );

      // ZapZap indicator should be visible
      expect(screen.getByText(/zapzap eligible/i)).toBeInTheDocument();

      // ZapZap button should be enabled
      const zapButton = screen.getByRole('button', { name: /zapzap/i });
      expect(zapButton).not.toBeDisabled();

      // Player calls ZapZap
      fireEvent.click(zapButton);

      // Verify ZapZap was called
      expect(onZapZap).toHaveBeenCalled();
    });

    it('should display round end with correct scoring', () => {
      const roundData = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 10 },
          { id: '2', username: 'Bob', hand: [2, 15], handValue: 6, score: 6, totalScore: 20 },
        ],
        zapZapCaller: null,
        roundNumber: 3,
      };

      const onContinue = vi.fn();

      render(<RoundEnd roundData={roundData} onContinue={onContinue} />);

      // Round title
      expect(screen.getByText(/round 3 complete/i)).toBeInTheDocument();

      // Both players shown
      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();

      // Alice has lowest hand (0 points)
      const aliceRow = screen.getByText('Alice').closest('.player-row');
      expect(aliceRow.className).toMatch(/lowest/i);

      // Continue button works
      const continueButton = screen.getByRole('button', { name: /continue/i });
      fireEvent.click(continueButton);
      expect(onContinue).toHaveBeenCalled();
    });
  });

  describe('Multi-Player Scenarios', () => {
    it('should handle 3-player game correctly', () => {
      const threePlayerGame = {
        partyId: 'party1',
        players: [
          { id: '1', username: 'Alice', cardCount: 5, score: 0 },
          { id: '2', username: 'Bob', cardCount: 5, score: 0 },
          { id: '3', username: 'Charlie', cardCount: 5, score: 0 },
        ],
        currentTurnId: '2',
        currentAction: 'play',
        myHand: [0, 14, 28, 42, 52],
        myUserId: '1',
      };

      render(
        <GameBoard
          gameState={threePlayerGame}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // All 3 players visible
      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
      expect(screen.getByText('Charlie')).toBeInTheDocument();

      // Not my turn (Bob's turn)
      expect(screen.getByText(/waiting/i)).toBeInTheDocument();
    });

    it('should handle 8-player game correctly', () => {
      const eightPlayerGame = {
        partyId: 'party1',
        players: [
          { id: '1', username: 'P1', cardCount: 5, score: 0 },
          { id: '2', username: 'P2', cardCount: 5, score: 0 },
          { id: '3', username: 'P3', cardCount: 5, score: 0 },
          { id: '4', username: 'P4', cardCount: 5, score: 0 },
          { id: '5', username: 'P5', cardCount: 5, score: 0 },
          { id: '6', username: 'P6', cardCount: 5, score: 0 },
          { id: '7', username: 'P7', cardCount: 5, score: 0 },
          { id: '8', username: 'P8', cardCount: 5, score: 0 },
        ],
        currentTurnId: '1',
        currentAction: 'play',
        myHand: [0, 14, 28, 42, 52],
        myUserId: '1',
      };

      const { container } = render(
        <GameBoard
          gameState={eightPlayerGame}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // All 8 players visible
      const playerCards = container.querySelectorAll('.player-card');
      expect(playerCards.length).toBe(8);
    });
  });

  describe('ZapZap Scenarios', () => {
    it('should display successful ZapZap', () => {
      const successfulZapZap = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 13, 26, 39], handValue: 4, score: 0, totalScore: 5 },
          { id: '2', username: 'Bob', hand: [2, 15, 28], handValue: 9, score: 9, totalScore: 20 },
        ],
        zapZapCaller: '1', // Alice called and won
        roundNumber: 2,
      };

      const { container } = render(<RoundEnd roundData={successfulZapZap} onContinue={vi.fn()} />);

      const zapIndicator = container.querySelector('.zapzap-indicator');
      expect(zapIndicator.textContent).toMatch(/alice/i);
      expect(zapIndicator.textContent).toMatch(/successful/i);
      expect(zapIndicator.className).toMatch(/successful/i);
    });

    it('should display counteracted ZapZap with penalty', () => {
      const counteractedZapZap = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 0, totalScore: 5 },
          { id: '2', username: 'Bob', hand: [0, 13, 26, 39], handValue: 4, score: 14, totalScore: 20 }, // Counteracted!
        ],
        zapZapCaller: '2', // Bob called but Alice had lower
        roundNumber: 2,
      };

      const { container } = render(<RoundEnd roundData={counteractedZapZap} onContinue={vi.fn()} />);

      const zapIndicator = container.querySelector('.zapzap-indicator');
      expect(zapIndicator.textContent).toMatch(/bob/i);
      expect(zapIndicator.textContent).toMatch(/counteract/i);
      expect(zapIndicator.className).toMatch(/counteracted/i);

      // Penalty calculation shown: 4 + (2 × 5) = 14
      expect(zapIndicator.textContent).toMatch(/penalty/i);
    });
  });

  describe('Elimination Scenarios', () => {
    it('should mark eliminated player correctly', () => {
      const withElimination = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 3, totalScore: 95 },
          { id: '2', username: 'Bob', hand: [10, 24], handValue: 23, score: 23, totalScore: 105 }, // Eliminated!
        ],
        zapZapCaller: null,
        roundNumber: 10,
      };

      const { container } = render(<RoundEnd roundData={withElimination} onContinue={vi.fn()} />);

      // Bob should be marked as eliminated
      const playerRows = container.querySelectorAll('.player-row');
      const bobRow = Array.from(playerRows).find((row) => row.textContent.includes('Bob'));
      expect(bobRow.className).toMatch(/eliminated/i);

      // Eliminations section should appear
      const eliminationsSection = container.querySelector('.eliminations');
      expect(eliminationsSection).toBeInTheDocument();
      expect(eliminationsSection.textContent).toMatch(/bob.*eliminated/i);
    });

    it('should handle multiple eliminations', () => {
      const multipleEliminations = {
        players: [
          { id: '1', username: 'Alice', hand: [0, 14], handValue: 3, score: 3, totalScore: 90 },
          { id: '2', username: 'Bob', hand: [10, 24], handValue: 23, score: 23, totalScore: 105 },
          { id: '3', username: 'Charlie', hand: [11, 25], handValue: 25, score: 25, totalScore: 110 },
        ],
        zapZapCaller: null,
        roundNumber: 12,
      };

      const { container } = render(<RoundEnd roundData={multipleEliminations} onContinue={vi.fn()} />);

      const eliminationsSection = container.querySelector('.eliminations');
      expect(eliminationsSection.textContent).toMatch(/bob/i);
      expect(eliminationsSection.textContent).toMatch(/charlie/i);
    });
  });

  describe('Turn Management', () => {
    it('should disable actions when not player turn', () => {
      const notMyTurn = {
        partyId: 'party1',
        players: [
          { id: '1', username: 'Alice', cardCount: 5, score: 0 },
          { id: '2', username: 'Bob', cardCount: 5, score: 0 },
        ],
        currentTurnId: '2', // Bob's turn
        currentAction: 'play',
        myHand: [0, 14, 28],
        myUserId: '1', // I'm Alice
      };

      render(
        <GameBoard
          gameState={notMyTurn}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // All action buttons disabled
      const playButton = screen.getByRole('button', { name: /play/i });
      const drawButton = screen.getByRole('button', { name: /draw/i });
      const zapButton = screen.getByRole('button', { name: /zapzap/i });

      expect(playButton).toBeDisabled();
      expect(drawButton).toBeDisabled();
      expect(zapButton).toBeDisabled();

      // Waiting message shown
      expect(screen.getByText(/waiting/i)).toBeInTheDocument();
    });

    it('should enable actions when player turn', () => {
      const myTurn = {
        partyId: 'party1',
        players: [
          { id: '1', username: 'Alice', cardCount: 3, score: 0 },
        ],
        currentTurnId: '1',
        currentAction: 'draw',
        myHand: [0, 14, 28],
        myUserId: '1',
      };

      render(
        <GameBoard
          gameState={myTurn}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      // Draw button enabled (currentAction = 'draw')
      const drawButton = screen.getByRole('button', { name: /draw/i });
      expect(drawButton).not.toBeDisabled();

      // Your turn message shown
      expect(screen.getByText(/your turn/i)).toBeInTheDocument();
    });
  });

  describe('Edge Cases', () => {
    it('should handle empty hand', () => {
      const emptyHand = {
        partyId: 'party1',
        players: [{ id: '1', username: 'Alice', cardCount: 0, score: 0 }],
        currentTurnId: '1',
        currentAction: 'play',
        myHand: [],
        myUserId: '1',
      };

      render(
        <GameBoard
          gameState={emptyHand}
          onPlay={vi.fn()}
          onDraw={vi.fn()}
          onZapZap={vi.fn()}
        />
      );

      expect(screen.getByText(/no cards/i)).toBeInTheDocument();
    });

    it('should handle loading state', () => {
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

    it('should handle round end with no players', () => {
      const emptyRound = {
        players: [],
        zapZapCaller: null,
        roundNumber: 1,
      };

      const { container } = render(<RoundEnd roundData={emptyRound} onContinue={vi.fn()} />);

      expect(container.textContent).toMatch(/no players|error/i);
    });
  });
});
