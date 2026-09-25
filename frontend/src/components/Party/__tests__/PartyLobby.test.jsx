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
        expect(screen.getByRole('button', { name: /start/i })).toBeInTheDocument();
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
      expect(screen.queryByRole('button', { name: /start/i })).not.toBeInTheDocument();
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
        const startButton = screen.getByRole('button', { name: /start/i });
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
        const startButton = screen.getByRole('button', { name: /start/i });
        expect(startButton).not.toBeDisabled();
      });
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

      const startButton = await screen.findByRole('button', { name: /start/i });
      fireEvent.click(startButton);

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/start');
        expect(mockNavigate).toHaveBeenCalledWith('/game/party-123');
      });
    });
  });
});
