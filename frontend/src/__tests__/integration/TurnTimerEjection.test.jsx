import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import GameBoard from '../../components/Game/GameBoard';
import PartyList from '../../components/Party/PartyList';
import { apiClient } from '../../services/api';
import { gameStateResponse, userIdOfSeat } from '../../test/gameState';

// The turn timer gives a late human's seat to a bot (GAME_RULES.md, Turn Time Limit) and
// tells their own stream with `playerReplaced`. Through the real router: the board sends
// them to the party list, which says why. The API, auth and SSE are mocked.
vi.mock('../../services/api');

const authState = vi.hoisted(() => ({ user: null }));
vi.mock('../../contexts/AuthContext', () => ({
  useAuth: () => ({ user: authState.user, logout: vi.fn() }),
}));

const sseHook = vi.hoisted(() => ({ onMessage: null }));
vi.mock('../../hooks/useSSE', () => ({
  default: (url, options) => {
    sseHook.onMessage = options?.onMessage;
    return { connected: true };
  },
}));

vi.mock('../../components/Party/ConnectedPlayers', () => ({ default: () => null }));

const EJECTED = 'Vous avez été retiré de la partie (temps dépassé)';

describe('Turn timer ejection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authState.user = { id: userIdOfSeat(0), username: 'Alice' };
    const now = Date.now();
    const state = gameStateResponse({
      extra: { turnTimeLimit: 30, turnDeadline: now + 1000, serverTime: now },
    });
    apiClient.get = vi.fn((url) =>
      Promise.resolve({ data: url === '/party' ? { success: true, parties: [] } : state })
    );
  });

  it('shows the message on the party list once the user\'s own seat went to a bot', async () => {
    render(
      <MemoryRouter initialEntries={['/game/party1']}>
        <Routes>
          <Route path="/game/:partyId" element={<GameBoard />} />
          <Route path="/parties" element={<PartyList />} />
        </Routes>
      </MemoryRouter>
    );
    expect(await screen.findByRole('timer')).toBeInTheDocument();

    act(() => {
      sseHook.onMessage({
        type: 'gameUpdate',
        partyId: 'party1',
        userId: userIdOfSeat(0),
        action: 'playerReplaced',
        playerIndex: 0,
        replacedUserId: userIdOfSeat(0),
        botId: 'bot-1',
      });
    });

    expect(await screen.findByRole('status')).toHaveTextContent(EJECTED);
    expect(screen.getByText(/available parties/i)).toBeInTheDocument();
    expect(apiClient.get).toHaveBeenCalledWith('/party');
  });

  it('shows nothing of it on the party list reached otherwise', async () => {
    render(
      <MemoryRouter initialEntries={['/parties']}>
        <Routes>
          <Route path="/parties" element={<PartyList />} />
        </Routes>
      </MemoryRouter>
    );

    expect(await screen.findByText(/available parties/i)).toBeInTheDocument();
    expect(screen.queryByText(EJECTED)).not.toBeInTheDocument();
  });
});
