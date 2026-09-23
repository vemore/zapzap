import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import GameBoard from '../../components/Game/GameBoard';
import RoundEnd from '../../components/Game/RoundEnd';
import { apiClient } from '../../services/api';
import { gameStateResponse, userIdOfSeat } from '../../test/gameState';

// Game flow through the real GameBoard: every action goes to the API, and the
// board re-reads `GET /game/:partyId/state` after it. The API answers from a
// scripted sequence of states; auth and SSE are mocked.
vi.mock('../../services/api');

const authState = vi.hoisted(() => ({ user: null }));
vi.mock('../../contexts/AuthContext', () => ({
  useAuth: () => ({ user: authState.user }),
}));

vi.mock('../../hooks/useSSE', () => ({ default: () => ({ connected: true }) }));

const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useNavigate: () => mockNavigate };
});

/** Serve these states in order; the last one repeats. */
function serveStates(...states) {
  const queue = states.map((options) => ({ data: gameStateResponse(options) }));
  apiClient.get = vi.fn(() => Promise.resolve(queue.length > 1 ? queue.shift() : queue[0]));
}

function renderBoard() {
  return render(
    <MemoryRouter initialEntries={['/game/party1']}>
      <Routes>
        <Route path="/game/:partyId" element={<GameBoard />} />
      </Routes>
    </MemoryRouter>
  );
}

const renderRoundEnd = (props) =>
  render(
    <MemoryRouter>
      <RoundEnd {...props} />
    </MemoryRouter>
  );

const playButton = () => screen.getByRole('button', { name: /^play/i });
const drawButton = () => screen.getByRole('button', { name: /^(draw|take)/i });
const zapZapButton = () => screen.getByRole('button', { name: /zapzap/i });
const cardOf = (name) => screen.getByText(name, { selector: 'span' }).closest('.p-5');

describe('Phase 8: Game Flow Integration Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authState.user = { id: userIdOfSeat(0), username: 'Alice' };
    apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });
  });

  describe('Complete Game Round Flow', () => {
    it('should complete a full turn: play, then draw, then wait', async () => {
      serveStates(
        { myHand: [0, 13, 28], currentAction: 'play' }, // A♠ A♥ 3♣
        { myHand: [28], currentAction: 'draw' },
        { myHand: [28, 5], currentTurn: 1, currentAction: 'play' }
      );

      renderBoard();

      // It is my turn to play
      expect(await screen.findByText(/your turn - play cards/i)).toBeInTheDocument();

      // I play the pair of aces
      fireEvent.click(screen.getByRole('button', { name: 'Card As' }));
      fireEvent.click(screen.getByRole('button', { name: 'Card Ah' }));
      expect(playButton()).not.toBeDisabled();
      fireEvent.click(playButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/play', { cardIds: [0, 13] });
      });

      // Then I must draw
      expect(await screen.findByText(/your turn - draw a card/i)).toBeInTheDocument();
      expect(playButton()).toBeDisabled();
      fireEvent.click(drawButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/draw', { source: 'deck' });
      });

      // Then it is Bob's turn
      expect(await screen.findByText(/waiting for other players/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Card 6s' })).toBeInTheDocument();
    });

    it('should handle ZapZap eligibility correctly', async () => {
      serveStates(
        { myHand: [0, 13, 26, 39] }, // Four Aces = 4 points (eligible!)
        {
          currentAction: 'finished',
          myHand: [0, 13, 26, 39],
          scores: [0, 9],
          extra: {
            zapZapCaller: 0,
            allHands: { 0: [0, 13, 26, 39], 1: [2, 15, 28] },
            handPoints: { 0: 4, 1: 9 },
            lowestHandPlayerIndex: 0,
            roundScores: { 0: 0, 1: 9 },
          },
        }
      );

      renderBoard();

      // ZapZap indicator is visible and the button enabled
      expect(await screen.findByText(/zapzap eligible/i)).toBeInTheDocument();
      expect(zapZapButton()).not.toBeDisabled();

      // I call ZapZap
      fireEvent.click(zapZapButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/zapzap');
      });

      // The round ends on my successful ZapZap
      const zapIndicator = (await screen.findByText(/successfully called/i)).closest('p');
      expect(zapIndicator).toHaveTextContent(/alice/i);
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

      renderRoundEnd({ roundData, onContinue });

      // Round title
      expect(screen.getByText(/round 3 complete/i)).toBeInTheDocument();

      // Both players shown
      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();

      // Alice has lowest hand (0 points)
      expect(cardOf('Alice')).toHaveTextContent(/lowest hand/i);

      // Continue button works
      const continueButton = screen.getByRole('button', { name: /continue/i });
      fireEvent.click(continueButton);
      expect(onContinue).toHaveBeenCalled();
    });
  });

  describe('Multi-Player Scenarios', () => {
    it('should handle 3-player game correctly', async () => {
      serveStates({
        usernames: ['Alice', 'Bob', 'Charlie'],
        currentTurn: 1, // Bob's turn
        myHand: [0, 14, 28, 42, 52],
      });

      renderBoard();

      // All 3 players visible
      expect(await screen.findByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
      expect(screen.getByText('Charlie')).toBeInTheDocument();

      // Not my turn (Bob's turn)
      expect(screen.getByText(/waiting for other players/i)).toBeInTheDocument();
    });

    it('should handle 8-player game correctly', async () => {
      const usernames = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7', 'P8'];
      serveStates({ usernames, myHand: [0, 14, 28, 42, 52] });

      const { container } = renderBoard();

      // All 8 players visible, each in its own row
      await screen.findByText('P1');
      usernames.forEach((name) => expect(screen.getByText(name)).toBeInTheDocument());
      expect(container.querySelectorAll('.border-l-4')).toHaveLength(8);
    });
  });

  describe('ZapZap Scenarios', () => {
    it('should display successful ZapZap', async () => {
      serveStates({
        currentAction: 'finished',
        roundNumber: 2,
        scores: [5, 20],
        extra: {
          zapZapCaller: 0, // Alice called and won
          allHands: { 0: [0, 13, 26, 39], 1: [2, 15, 28] },
          handPoints: { 0: 4, 1: 9 },
          lowestHandPlayerIndex: 0,
          roundScores: { 0: 0, 1: 9 },
        },
      });

      renderBoard();

      const zapIndicator = (await screen.findByText(/successfully called/i)).closest('p');
      expect(zapIndicator).toHaveTextContent(/alice/i);
      expect(zapIndicator.closest('.border-2').className).toMatch(/green/);
      expect(cardOf('Alice')).toHaveTextContent('ZapZap');
    });

    it('should display counteracted ZapZap with penalty', async () => {
      serveStates({
        currentAction: 'finished',
        roundNumber: 2,
        scores: [5, 20],
        extra: {
          zapZapCaller: 1, // Bob called but Alice had lower
          wasCounterActed: true,
          allHands: { 0: [0, 14], 1: [0, 13, 26, 39] },
          handPoints: { 0: 3, 1: 4 },
          lowestHandPlayerIndex: 0,
          roundScores: { 0: 0, 1: 9 },
        },
      });

      renderBoard();

      const zapIndicator = (await screen.findByText(/called zapzap but was/i)).closest('p');
      expect(zapIndicator).toHaveTextContent(/bob/i);
      expect(zapIndicator).toHaveTextContent(/counteracted/i);
      expect(zapIndicator.closest('.border-2').className).toMatch(/red/);

      // Penalty calculation shown: 4 + ((2 − 1) × 5) = 9 (GAME_RULES.md)
      expect(screen.getByText(/penalty/i)).toHaveTextContent('Penalty: 4 + (1 × 5) = 9 points');
    });
  });

  describe('Elimination Scenarios', () => {
    it('should mark eliminated player correctly', async () => {
      serveStates({
        currentAction: 'finished',
        roundNumber: 10,
        scores: [95, 105], // Bob is past 100
        extra: {
          allHands: { 0: [0, 14], 1: [10, 24] },
          handPoints: { 0: 3, 1: 23 },
          lowestHandPlayerIndex: 0,
          roundScores: { 0: 0, 1: 23 },
        },
      });

      renderBoard();

      // Bob should be marked as eliminated
      await screen.findByText(/round 10 complete/i);
      expect(cardOf('Bob')).toHaveTextContent('Eliminated');
      expect(cardOf('Alice')).not.toHaveTextContent('Eliminated');

      // Eliminations section should appear
      const eliminationsSection = screen.getByText('Eliminated Players').closest('.p-6');
      expect(eliminationsSection).toHaveTextContent(/bob eliminated with 105 points/i);
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

      renderRoundEnd({ roundData: multipleEliminations, onContinue: vi.fn() });

      const eliminationsSection = screen.getByText('Eliminated Players').closest('.p-6');
      expect(eliminationsSection).toHaveTextContent(/bob/i);
      expect(eliminationsSection).toHaveTextContent(/charlie/i);
      expect(eliminationsSection).not.toHaveTextContent(/alice/i);
    });
  });

  describe('Turn Management', () => {
    it('should disable actions when not player turn', async () => {
      serveStates({ currentTurn: 1, myHand: [0, 14, 28] }); // Bob's turn, I'm Alice

      renderBoard();
      await screen.findByText('Alice');

      // All action buttons disabled
      expect(playButton()).toBeDisabled();
      expect(drawButton()).toBeDisabled();
      expect(zapZapButton()).toBeDisabled();

      // Waiting message shown
      expect(screen.getByText(/waiting for other players/i)).toBeInTheDocument();
    });

    it('should enable actions when player turn', async () => {
      serveStates({ currentTurn: 0, currentAction: 'draw', myHand: [0, 14, 28] });

      renderBoard();
      await screen.findByText('Alice');

      // Draw button enabled (currentAction = 'draw')
      expect(drawButton()).not.toBeDisabled();

      // Your turn message shown
      expect(screen.getByText(/your turn/i)).toBeInTheDocument();
    });
  });

  describe('Edge Cases', () => {
    it('should handle empty hand', async () => {
      serveStates({ myHand: [] });

      renderBoard();

      expect(await screen.findByText(/no cards/i)).toBeInTheDocument();
    });

    it('should handle loading state', () => {
      apiClient.get = vi.fn(() => new Promise(() => {})); // never answers

      renderBoard();

      expect(screen.getByText(/loading/i)).toBeInTheDocument();
    });

    it('should handle round end with no players', () => {
      const emptyRound = {
        players: [],
        zapZapCaller: null,
        roundNumber: 1,
      };

      const { container } = renderRoundEnd({ roundData: emptyRound, onContinue: vi.fn() });

      expect(container.textContent).toMatch(/no players|error/i);
    });
  });
});
