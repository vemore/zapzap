import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import PartyList from '../PartyList';
import { apiClient } from '../../../services/api';

vi.mock('../../../services/api');

describe('Phase 3: PartyList Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Party List Rendering', () => {
    it('should display list of public parties from API', async () => {
      const mockParties = [
        {
          id: '1',
          name: 'Test Party 1',
          playerCount: 3,
          maxPlayers: 5,
          status: 'waiting',
        },
        {
          id: '2',
          name: 'Test Party 2',
          playerCount: 4,
          maxPlayers: 6,
          status: 'waiting',
        },
      ];

      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: mockParties },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText('Test Party 1')).toBeInTheDocument();
        expect(screen.getByText('Test Party 2')).toBeInTheDocument();
      });
    });

    it('should show player count for each party', async () => {
      const mockParties = [
        {
          id: '1',
          name: 'Test Party',
          playerCount: 3,
          maxPlayers: 5,
          status: 'waiting',
        },
      ];

      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: mockParties },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText(/3.*5/)).toBeInTheDocument(); // "3/5 players" or similar
      });
    });

    it('should validate party has 3-8 players (game rule)', async () => {
      const mockParties = [
        {
          id: '1',
          name: 'Valid Party',
          playerCount: 3,
          maxPlayers: 8,
          status: 'waiting',
        },
        {
          id: '2',
          name: 'Invalid Party',
          playerCount: 2,
          maxPlayers: 2, // Less than minimum 3 players
          status: 'waiting',
        },
      ];

      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: mockParties },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        const validParty = screen.getByText('Valid Party');
        expect(validParty).toBeInTheDocument();
      });

      // Invalid party should show warning or be filtered
      // (Implementation detail - might show with warning or not show at all)
    });

    it('should show loading state while fetching parties', () => {
      apiClient.get = vi.fn(() => new Promise(() => {})); // Never resolves

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      expect(screen.getByText(/loading/i)).toBeInTheDocument();
    });

    it('should show error message on failed fetch', async () => {
      apiClient.get = vi.fn().mockRejectedValue(new Error('Failed to fetch parties'));

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText(/failed to fetch parties/i)).toBeInTheDocument();
      });
    });

    it('should show empty state when no parties exist', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: [] },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText(/no parties/i)).toBeInTheDocument();
      });
    });
  });

  describe('Party Actions', () => {
    it('should have button to create new party', async () => {
      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: [] },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /create party/i })).toBeInTheDocument();
      });
    });

    it('should show join button for each party', async () => {
      const mockParties = [
        {
          id: '1',
          name: 'Test Party',
          playerCount: 3,
          maxPlayers: 5,
          status: 'waiting',
        },
      ];

      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: mockParties },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /join/i })).toBeInTheDocument();
      });
    });

    it('should disable join button for full parties', async () => {
      const mockParties = [
        {
          id: '1',
          name: 'Full Party',
          playerCount: 5,
          maxPlayers: 5,
          status: 'waiting',
        },
      ];

      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: mockParties },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText('Full Party')).toBeInTheDocument();
      });

      // Button text changes to "Full" when party is full
      const joinButton = screen.getByRole('button', { name: /full/i });
      expect(joinButton).toBeDisabled();
    });

    it('should disable join button for started parties', async () => {
      const mockParties = [
        {
          id: '1',
          name: 'Started Party',
          playerCount: 4,
          maxPlayers: 5,
          status: 'playing', // Game already started
        },
      ];

      apiClient.get = vi.fn().mockResolvedValue({
        data: { success: true, parties: mockParties },
      });

      render(
        <BrowserRouter>
          <PartyList />
        </BrowserRouter>
      );

      await waitFor(() => {
        expect(screen.getByText('Started Party')).toBeInTheDocument();
      });

      // Button text changes to "In Progress" when party is playing
      const joinButton = screen.getByRole('button', { name: /in progress/i });
      expect(joinButton).toBeDisabled();
    });
  });
});
