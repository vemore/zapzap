import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import GameBoard from '../GameBoard';
import { apiClient } from '../../../services/api';
import { gameStateResponse, userIdOfSeat } from '../../../test/gameState';

// GameBoard is the /game/:partyId route: it loads its state from the API, acts
// through the API and refreshes on SSE events. The API, the signed-in user and
// the SSE hook are mocked; the child components are the real ones.
vi.mock('../../../services/api');

const authState = vi.hoisted(() => ({ user: null }));
vi.mock('../../../contexts/AuthContext', () => ({
  useAuth: () => ({ user: authState.user }),
}));

const sseHook = vi.hoisted(() => ({ urls: [] }));
vi.mock('../../../hooks/useSSE', () => ({
  default: (url) => {
    sseHook.urls.push(url);
    return { connected: true };
  },
}));

const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useNavigate: () => mockNavigate };
});

function serveState(options) {
  apiClient.get = vi.fn().mockResolvedValue({ data: gameStateResponse(options) });
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

// The action buttons show their label from the `sm` breakpoint; the accessible
// name is the label text, present in the DOM at every width.
const playButton = () => screen.getByRole('button', { name: /^play/i });
const drawButton = () => screen.getByRole('button', { name: /^(draw|take)/i });
const zapZapButton = () => screen.getByRole('button', { name: /zapzap/i });
const handCards = () => document.querySelectorAll('.card-fan [role="button"]');

describe('Phase 5: GameBoard Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authState.user = { id: userIdOfSeat(0), username: 'Alice' };
    apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });
  });

  describe('Real-time stream', () => {
    it('opens /suscribeupdate with the URL-encoded token of the signed-in user', async () => {
      localStorage.setItem('token', 'a.b/c+d=');
      sseHook.urls = [];
      serveState({ myHand: [0] });

      renderBoard();

      await waitFor(() => expect(sseHook.urls.length).toBeGreaterThan(0));
      expect(sseHook.urls.at(-1)).toBe(
        `${window.location.origin}/suscribeupdate?token=a.b%2Fc%2Bd%3D`
      );
      localStorage.removeItem('token');
    });
  });

  describe('Component Integration', () => {
    it('should render all sub-components', async () => {
      serveState({ myHand: [0, 14, 28] }); // A♠ 2♥ 3♣

      renderBoard();

      // PlayerTable
      expect(await screen.findByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();

      // PlayerHand
      expect(handCards()).toHaveLength(3);

      // ActionButtons
      expect(playButton()).toBeInTheDocument();
      expect(drawButton()).toBeInTheDocument();
      expect(zapZapButton()).toBeInTheDocument();
    });

    it('should load the state of the party in the URL', async () => {
      serveState();

      renderBoard();

      await screen.findByText('Alice');
      expect(apiClient.get).toHaveBeenCalledWith('/game/party1/state');
    });

    it('should pass correct props to PlayerTable', async () => {
      serveState({ currentTurn: 1, handSizes: [3, 7] });

      renderBoard();

      // Bob (seat 1) has the turn; his hand size comes from otherPlayersHandSizes
      const bobRow = (await screen.findByText('Bob')).closest('.border-l-4');
      expect(bobRow.className).toMatch(/border-green-400/);
      expect(bobRow).toHaveTextContent('(7)');
    });

    it('should pass correct props to PlayerHand', async () => {
      serveState({ myHand: [0, 14, 28] });

      renderBoard();

      await screen.findByText('Alice');
      expect(screen.getByRole('button', { name: 'Card As' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Card 2h' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Card 3c' })).toBeInTheDocument();
    });

    it('should pass correct props to ActionButtons', async () => {
      serveState({ currentTurn: 0, currentAction: 'play' });

      renderBoard();

      expect(await screen.findByText(/your turn - play cards/i)).toBeInTheDocument();
    });
  });

  describe('Card Selection Flow', () => {
    it('should update selected cards when cards are clicked', async () => {
      serveState({ myHand: [0, 13, 28] }); // A♠ A♥ 3♣

      renderBoard();
      await screen.findByText('Alice');

      fireEvent.click(screen.getByRole('button', { name: 'Card As' }));
      fireEvent.click(screen.getByRole('button', { name: 'Card Ah' }));

      expect(screen.getByRole('button', { name: 'Card As' })).toHaveAttribute('aria-selected', 'true');
      expect(screen.getByRole('button', { name: 'Card Ah' })).toHaveAttribute('aria-selected', 'true');
      expect(screen.getByRole('button', { name: 'Card 3c' })).toHaveAttribute('aria-selected', 'false');
      expect(playButton()).toHaveTextContent('2');
    });

    it('should validate selected cards before enabling play', async () => {
      serveState({ myHand: [0, 14, 28] }); // A♠ 2♥ 3♣

      renderBoard();
      await screen.findByText('Alice');

      // A♠ + 2♥: neither a pair nor a same-suit sequence
      fireEvent.click(screen.getByRole('button', { name: 'Card As' }));
      fireEvent.click(screen.getByRole('button', { name: 'Card 2h' }));

      expect(playButton()).toBeDisabled();
      expect(screen.getByRole('alert')).toBeInTheDocument();
    });
  });

  describe('Action Handlers', () => {
    it('should call onPlay with selected cards', async () => {
      serveState({ myHand: [0, 13, 28] }); // A♠ A♥ 3♣

      renderBoard();
      await screen.findByText('Alice');

      fireEvent.click(screen.getByRole('button', { name: 'Card As' }));
      fireEvent.click(screen.getByRole('button', { name: 'Card Ah' }));
      fireEvent.click(playButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/play', { cardIds: [0, 13] });
      });
    });

    it('should call onDraw when draw button clicked', async () => {
      serveState({ currentAction: 'draw' });

      renderBoard();
      await screen.findByText('Alice');

      fireEvent.click(drawButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/draw', { source: 'deck' });
      });
    });

    it('should call onZapZap when zapzap button clicked', async () => {
      serveState({ myHand: [0, 13, 26, 39] }); // four aces = 4 points

      renderBoard();
      await screen.findByText('Alice');

      fireEvent.click(zapZapButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/zapzap');
      });
    });

    it('should show the error the API returns for a refused action', async () => {
      serveState({ currentAction: 'draw' });
      apiClient.post = vi.fn().mockRejectedValue({ response: { data: { error: 'Not your turn' } } });

      renderBoard();
      await screen.findByText('Alice');

      fireEvent.click(drawButton());

      expect(await screen.findByText('Not your turn')).toBeInTheDocument();
    });
  });

  describe('Turn State Management', () => {
    it('should disable actions when not my turn', async () => {
      serveState({ currentTurn: 1, myHand: [0, 13, 26, 39] });

      renderBoard();
      await screen.findByText('Alice');

      expect(playButton()).toBeDisabled();
      expect(drawButton()).toBeDisabled();
      expect(zapZapButton()).toBeDisabled();

      // Cards cannot be selected either
      fireEvent.click(screen.getByRole('button', { name: 'Card As' }));
      expect(screen.getByRole('button', { name: 'Card As' })).toHaveAttribute('aria-selected', 'false');
    });

    it('should show waiting message when not my turn', async () => {
      serveState({ currentTurn: 1 });

      renderBoard();

      expect(await screen.findByText(/waiting for other players/i)).toBeInTheDocument();
    });
  });

  describe('ZapZap Eligibility', () => {
    it('should enable zapzap when hand ≤5 points', async () => {
      serveState({ myHand: [0, 13, 26, 39] }); // 4 points

      renderBoard();
      await screen.findByText('Alice');

      expect(zapZapButton()).not.toBeDisabled();
    });

    it('should disable zapzap when hand >5 points', async () => {
      serveState({ myHand: [0, 14, 28] }); // 1 + 2 + 3 = 6 points

      renderBoard();
      await screen.findByText('Alice');

      expect(zapZapButton()).toBeDisabled();
    });
  });

  describe('Edge Cases', () => {
    it('should show loading when no game state', () => {
      apiClient.get = vi.fn(() => new Promise(() => {})); // never answers

      renderBoard();

      expect(screen.getByText(/loading game/i)).toBeInTheDocument();
    });

    it('should report a game that has not started', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: { ...gameStateResponse(), gameState: null },
      });

      renderBoard();

      expect(await screen.findByText(/game has not started yet/i)).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: /back to lobby/i }));
      expect(mockNavigate).toHaveBeenCalledWith('/party/party1');
    });

    it('should report a failed load', async () => {
      apiClient.get = vi.fn().mockRejectedValue(new Error('network'));

      renderBoard();

      expect(await screen.findByText(/failed to load game state/i)).toBeInTheDocument();
    });

    it('should handle missing hand gracefully', async () => {
      serveState({ myHand: [] });

      renderBoard();

      expect(await screen.findByText(/no cards in hand/i)).toBeInTheDocument();
    });
  });

  describe('Round Phases', () => {
    it('should ask the starting player for the hand size', async () => {
      serveState({ currentAction: 'selectHandSize', myHand: [] });

      renderBoard();

      fireEvent.click(await screen.findByRole('button', { name: '6' }));
      fireEvent.click(screen.getByRole('button', { name: /confirm/i }));

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/selectHandSize', { handSize: 6 });
      });
    });

    it('should show the round end once the round is finished', async () => {
      serveState({
        currentAction: 'finished',
        roundNumber: 2,
        extra: {
          allHands: { 0: [0], 1: [2, 15] },
          handPoints: { 0: 1, 1: 6 },
          lowestHandPlayerIndex: 0,
          roundScores: { 0: 0, 1: 6 },
        },
      });

      renderBoard();

      expect(await screen.findByText(/round 2 complete/i)).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: /continue to next round/i }));

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/game/party1/nextRound');
      });
    });
  });
});
