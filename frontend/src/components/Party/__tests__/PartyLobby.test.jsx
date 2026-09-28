import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import PartyLobby from '../PartyLobby';
import { apiClient } from '../../../services/api';

vi.mock('../../../services/api');

// The signed-in user, switchable per test
const authState = vi.hoisted(() => ({ user: null }));
vi.mock('../../../contexts/AuthContext', () => ({
  useAuth: () => ({ user: authState.user, logout: vi.fn() }),
}));

// No real EventSource in these tests
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
  return {
    ...actual,
    useNavigate: () => mockNavigate,
    useParams: () => ({ partyId: 'party-123' }),
  };
});

/** GET /party/:id answers `{ party, players }` */
function mockPartyResponse({ ownerId = 'user-1', players = [], settings, status = 'waiting' } = {}) {
  apiClient.get = vi.fn().mockResolvedValue({
    data: {
      success: true,
      party: {
        id: 'party-123',
        name: 'Test Party',
        ownerId,
        status,
        ...(settings ? { settings } : {}),
      },
      players,
    },
  });
}

/** GET /party/:id as mockPartyResponse, and GET /bots listing `bots` */
function mockPartyAndBots({ players = [], bots = [] } = {}) {
  const party = {
    id: 'party-123',
    name: 'Test Party',
    ownerId: 'user-1',
    status: 'waiting',
    settings: { playerCount: 4 },
  };
  apiClient.get = vi.fn((url) =>
    Promise.resolve({
      data: url === '/bots' ? { success: true, bots } : { success: true, party, players },
    })
  );
}

const bot = (id, username, botDifficulty) => ({ id, username, userType: 'bot', botDifficulty });

function renderLobby() {
  return render(
    <BrowserRouter>
      <PartyLobby />
    </BrowserRouter>
  );
}

describe('Phase 3: PartyLobby Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authState.user = { id: 'user-1', username: 'TestUser' };
  });

  describe('Real-time stream', () => {
    it('opens /suscribeupdate with the URL-encoded token of the signed-in user', async () => {
      localStorage.setItem('token', 'a.b/c+d=');
      sseHook.urls = [];
      mockPartyResponse();

      renderLobby();

      await waitFor(() => expect(sseHook.urls.length).toBeGreaterThan(0));
      expect(sseHook.urls.at(-1)).toBe(
        `${window.location.origin}/suscribeupdate?token=a.b%2Fc%2Bd%3D`
      );
      localStorage.removeItem('token');
    });
  });

  describe('Party Display', () => {
    it('should show all joined players', async () => {
      mockPartyResponse({
        players: [
          { userId: 'user-1', username: 'Player1' },
          { userId: 'user-2', username: 'Player2' },
          { userId: 'user-3', username: 'Player3' },
        ],
      });

      renderLobby();

      await waitFor(() => {
        expect(screen.getByText('Player1')).toBeInTheDocument();
        expect(screen.getByText('Player2')).toBeInTheDocument();
        expect(screen.getByText('Player3')).toBeInTheDocument();
      });
    });

    it('should display party settings', async () => {
      mockPartyResponse({
        players: [],
        settings: {
          playerCount: 5,
          handSize: 7,
        },
      });

      renderLobby();

      await waitFor(() => {
        expect(screen.getByText('5 players')).toBeInTheDocument();
        expect(screen.getByText('7 cards')).toBeInTheDocument();
      });
    });

    it('shows the turn timer when the party was created with one', async () => {
      mockPartyResponse({ settings: { playerCount: 4, turnTimeLimit: 30 } });

      renderLobby();

      expect(await screen.findByTestId('turn-timer-setting')).toHaveTextContent(/turn timer:\s*30 s per turn/i);
    });

    it('shows no turn timer when it is off', async () => {
      mockPartyResponse({ settings: { playerCount: 4, turnTimeLimit: 0 } });

      renderLobby();

      expect(await screen.findByText('4 players')).toBeInTheDocument();
      expect(screen.queryByTestId('turn-timer-setting')).not.toBeInTheDocument();
    });
  });

  describe('Start Button (Game Rule Compliance)', () => {
    it('should only show start button for party owner', async () => {
      mockPartyResponse({
        ownerId: 'user-1', // Current user is owner
        players: [
          { userId: 'user-1', username: 'Owner' },
          { userId: 'user-2', username: 'Player2' },
          { userId: 'user-3', username: 'Player3' },
        ],
      });

      renderLobby();

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /start game/i })).toBeInTheDocument();
      });
    });

    it('should NOT show start button for non-owner', async () => {
      authState.user = { id: 'user-2', username: 'NonOwner' };

      mockPartyResponse({
        ownerId: 'user-1', // Different user is owner
        players: [
          { userId: 'user-1', username: 'Owner' },
          { userId: 'user-2', username: 'NonOwner' },
        ],
      });

      renderLobby();

      await waitFor(() => {
        expect(screen.getByText('Test Party')).toBeInTheDocument();
      });
      expect(screen.queryByRole('button', { name: /start game/i })).not.toBeInTheDocument();
    });

    it('should disable start button if less than 3 players (game rule)', async () => {
      mockPartyResponse({
        players: [
          { userId: 'user-1', username: 'Player1' },
          { userId: 'user-2', username: 'Player2' },
        ], // Only 2 players, need minimum 3
      });

      renderLobby();

      await waitFor(() => {
        const startButton = screen.getByRole('button', { name: /start game/i });
        expect(startButton).toBeDisabled();
      });
      expect(screen.getByText(/need 1 more player to start/i)).toBeInTheDocument();
    });

    it('should enable start button with 3+ players', async () => {
      mockPartyResponse({
        players: [
          { userId: 'user-1', username: 'Player1' },
          { userId: 'user-2', username: 'Player2' },
          { userId: 'user-3', username: 'Player3' },
        ], // 3 players - minimum met
      });

      renderLobby();

      await waitFor(() => {
        const startButton = screen.getByRole('button', { name: /start game/i });
        expect(startButton).not.toBeDisabled();
      });
    });
  });

  describe('Bots in free seats', () => {
    const owner = { userId: 'user-1', username: 'Owner' };
    const seatedEasy = { userId: 'b1', username: 'EasyBot1', userType: 'bot', botDifficulty: 'easy' };

    it('the owner adds a bot of a level to a free seat, which the seat list then shows', async () => {
      mockPartyAndBots({
        players: [owner, seatedEasy],
        bots: [bot('b1', 'EasyBot1', 'easy'), bot('b2', 'EasyBot2', 'easy'), bot('m1', 'MediumBot1', 'medium')],
      });
      apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });

      renderLobby();

      const select = await screen.findByLabelText('Add a bot to free seat 1');
      // EasyBot1 already sits here: one easy left; no hard bot at all
      expect(screen.getAllByRole('option', { name: 'Hard (none available)' })[0]).toBeDisabled();
      fireEvent.change(select, { target: { value: 'easy' } });

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/bots', { botId: 'b2' });
      });
      // The details are read again at once, not only on the event
      await waitFor(() => {
        expect(apiClient.get.mock.calls.filter(([url]) => url === '/party/party-123').length).toBe(2);
      });
      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('a guest sees no add-bot menu and no fill button', async () => {
      authState.user = { id: 'user-2', username: 'Guest' };
      mockPartyAndBots({ players: [owner, { userId: 'user-2', username: 'Guest' }] });

      renderLobby();

      await screen.findByText('Test Party');
      expect(screen.queryByLabelText(/add a bot/i)).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /fill with bots/i })).not.toBeInTheDocument();
    });

    it('fill with bots and start: the dialog picks a level, then the game opens', async () => {
      mockPartyAndBots({ players: [owner] });
      apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });

      renderLobby();

      fireEvent.click(await screen.findByRole('button', { name: /fill with bots and start/i }));
      const dialog = screen.getByRole('dialog', { name: 'Fill with bots' });
      expect(dialog).toBeInTheDocument();
      for (const level of ['Easy', 'Medium', 'Hard']) {
        expect(screen.getByLabelText(level)).toBeInTheDocument();
      }
      fireEvent.click(screen.getByLabelText('Hard'));
      fireEvent.click(screen.getByRole('button', { name: /^start$/i }));

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/fill-and-start', { difficulty: 'hard' });
        expect(mockNavigate).toHaveBeenCalledWith('/game/party-123');
      });
    });

    it('a fill refused for want of bots says so and stays', async () => {
      mockPartyAndBots({ players: [owner] });
      apiClient.post = vi.fn().mockRejectedValue({
        response: { status: 409, data: { error: 'Not enough bots', code: 'NOT_ENOUGH_BOTS' } },
      });

      renderLobby();

      fireEvent.click(await screen.findByRole('button', { name: /fill with bots and start/i }));
      fireEvent.click(screen.getByRole('button', { name: /^start$/i }));

      expect(await screen.findByRole('alert')).toHaveTextContent('Not enough bots available to fill the table.');
      expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/fill-and-start', { difficulty: 'medium' });
      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('cancelling the dialog seats nobody', async () => {
      mockPartyAndBots({ players: [owner] });
      apiClient.post = vi.fn();

      renderLobby();

      fireEvent.click(await screen.findByRole('button', { name: /fill with bots and start/i }));
      fireEvent.click(screen.getByRole('button', { name: /cancel/i }));

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
      expect(apiClient.post).not.toHaveBeenCalled();
    });
  });

  describe('Party Actions', () => {
    it('should allow players to leave party', async () => {
      mockPartyResponse({
        ownerId: 'user-2',
        players: [
          { userId: 'user-1', username: 'TestUser' },
        ],
      });

      apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });

      renderLobby();

      const leaveButton = await screen.findByRole('button', { name: /leave/i });
      fireEvent.click(leaveButton);

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/leave');
        expect(mockNavigate).toHaveBeenCalledWith('/parties');
      });
    });

    it('should start game and navigate to game view', async () => {
      mockPartyResponse({
        players: [
          { userId: 'user-1', username: 'Player1' },
          { userId: 'user-2', username: 'Player2' },
          { userId: 'user-3', username: 'Player3' },
        ],
      });

      apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });

      renderLobby();

      const startButton = await screen.findByRole('button', { name: /start game/i });
      fireEvent.click(startButton);

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/start');
        expect(mockNavigate).toHaveBeenCalledWith('/game/party-123');
      });
    });
  });
});
