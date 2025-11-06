import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import PartyLobby from '../PartyLobby';
import { apiClient } from '../../../services/api';
import * as auth from '../../../services/auth';

vi.mock('../../../services/api');
vi.mock('../../../services/auth');

const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
    useParams: () => ({ partyId: 'party-123' }),
  };
});

describe('Phase 3: PartyLobby Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    auth.getCurrentUser = vi.fn().mockReturnValue({ id: 'user-1', username: 'TestUser' });
  });

  describe('Party Display', () => {
    it('should show all joined players', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-1',
            players: [
              { userId: 'user-1', username: 'Player1' },
              { userId: 'user-2', username: 'Player2' },
              { userId: 'user-3', username: 'Player3' },
            ],
            status: 'waiting',
          },
        },
      });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText('Player1')).toBeInTheDocument();
        expect(screen.getByText('Player2')).toBeInTheDocument();
        expect(screen.getByText('Player3')).toBeInTheDocument();
      });
    });

    it('should display party settings', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-1',
            players: [],
            status: 'waiting',
            settings: {
              playerCount: 5,
              handSize: 7,
            },
          },
        },
      });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText(/5.*players/i)).toBeInTheDocument();
        expect(screen.getByText(/7.*cards/i)).toBeInTheDocument();
      });
    });
  });

  describe('Start Button (Game Rule Compliance)', () => {
    it('should only show start button for party owner', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-1', // Current user is owner
            players: [
              { userId: 'user-1', username: 'Owner' },
              { userId: 'user-2', username: 'Player2' },
              { userId: 'user-3', username: 'Player3' },
            ],
            status: 'waiting',
          },
        },
      });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /start/i })).toBeInTheDocument();
      });
    });

    it('should NOT show start button for non-owner', async () => {
      auth.getCurrentUser = vi.fn().mockReturnValue({ id: 'user-2', username: 'NonOwner' });

      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-1', // Different user is owner
            players: [
              { userId: 'user-1', username: 'Owner' },
              { userId: 'user-2', username: 'NonOwner' },
            ],
            status: 'waiting',
          },
        },
      });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.queryByRole('button', { name: /start/i })).not.toBeInTheDocument();
      });
    });

    it('should disable start button if less than 3 players (game rule)', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-1',
            players: [
              { userId: 'user-1', username: 'Player1' },
              { userId: 'user-2', username: 'Player2' },
            ], // Only 2 players, need minimum 3
            status: 'waiting',
          },
        },
      });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        const startButton = screen.getByRole('button', { name: /start/i });
        expect(startButton).toBeDisabled();
      });
    });

    it('should enable start button with 3+ players', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-1',
            players: [
              { userId: 'user-1', username: 'Player1' },
              { userId: 'user-2', username: 'Player2' },
              { userId: 'user-3', username: 'Player3' },
            ], // 3 players - minimum met
            status: 'waiting',
          },
        },
      });

      apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        const startButton = screen.getByRole('button', { name: /start/i });
        expect(startButton).not.toBeDisabled();
      });
    });
  });

  describe('Party Actions', () => {
    it('should allow players to leave party', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-2',
            players: [
              { userId: 'user-1', username: 'TestUser' },
            ],
            status: 'waiting',
          },
        },
      });

      apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        const leaveButton = screen.getByRole('button', { name: /leave/i });
        fireEvent.click(leaveButton);
      });

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/leave');
      });
    });

    it('should start game and navigate to game view', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: {
            id: 'party-123',
            name: 'Test Party',
            ownerId: 'user-1',
            players: [
              { userId: 'user-1', username: 'Player1' },
              { userId: 'user-2', username: 'Player2' },
              { userId: 'user-3', username: 'Player3' },
            ],
            status: 'waiting',
          },
        },
      });

      apiClient.post = vi.fn().mockResolvedValue({ data: { success: true } });

      render(
        <BrowserRouter>
          <PartyLobby />
        </BrowserRouter>
      );

      await waitFor(() => {
        const startButton = screen.getByRole('button', { name: /start/i });
        fireEvent.click(startButton);
      });

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith('/party/party-123/start');
        expect(mockNavigate).toHaveBeenCalledWith('/game/party-123');
      });
    });
  });
});
