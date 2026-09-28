import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import CreateParty from '../CreateParty';
import { apiClient } from '../../../services/api';

vi.mock('../../../services/api');

const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// The hand size is not a party setting any more: the starting player picks it
// at the start of each round (GAME_RULES.md, Round Start) — HandSizeSelector.

function renderCreateParty() {
  return render(
    <BrowserRouter>
      <CreateParty />
    </BrowserRouter>
  );
}

function fillForm({ name = 'Test Party', playerCount = '5' } = {}) {
  fireEvent.change(screen.getByLabelText(/party name/i), { target: { value: name } });
  fireEvent.change(screen.getByLabelText(/player count/i), { target: { value: playerCount } });
}

const createButton = () => screen.getByRole('button', { name: /create party/i });

describe('Phase 3: CreateParty Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    apiClient.get = vi.fn().mockResolvedValue({ data: { bots: [] } });
  });

  describe('Form Rendering', () => {
    it('should render create party form with all fields', () => {
      renderCreateParty();

      expect(screen.getByLabelText(/party name/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/player count/i)).toBeInTheDocument();
      expect(createButton()).toBeInTheDocument();
    });

    it('should have visibility toggle (public/private)', () => {
      renderCreateParty();

      expect(screen.getByLabelText(/visibility/i)).toBeInTheDocument();
    });

    it('asks for the number of seats only, no human or bot per seat', () => {
      renderCreateParty();

      // Name, seats, visibility: the free seats are filled in the lobby
      expect(screen.getAllByRole('combobox')).toHaveLength(1);
      expect(screen.queryByText(/waiting for human/i)).not.toBeInTheDocument();
      expect(screen.getByTestId('seats-hint')).toHaveTextContent(/add bots to the free seats in the lobby/i);
      expect(apiClient.get).not.toHaveBeenCalled();
    });
  });

  describe('Turn timer', () => {
    const timerChoice = (name) => screen.getByRole('radio', { name });
    const createdSettings = () => apiClient.post.mock.calls[0][1].settings;

    beforeEach(() => {
      apiClient.post = vi.fn().mockResolvedValue({ data: { party: { id: '1' } } });
    });

    it('offers off, 30 s, 60 s and 2 min whatever the seat count, off by default', () => {
      renderCreateParty();

      expect(screen.getByRole('group', { name: /turn timer/i })).toBeInTheDocument();
      expect(screen.getAllByRole('radio', { name: /^(off|30 s|60 s|2 min)$/i })).toHaveLength(4);
      expect(timerChoice('Off')).toBeChecked();
      expect(screen.getByTestId('turn-timer-hint')).toHaveTextContent(/at least two human players/i);

      // Creation does not know who will be human: the choice stays at every seat count
      fillForm({ playerCount: '3' });
      expect(timerChoice('2 min')).toBeInTheDocument();
    });

    it('sends the chosen limit in seconds', async () => {
      renderCreateParty();
      fillForm();
      fireEvent.click(timerChoice('30 s'));
      expect(timerChoice('30 s')).toBeChecked();
      fireEvent.click(createButton());

      await waitFor(() => expect(apiClient.post).toHaveBeenCalled());
      expect(createdSettings()).toEqual({ playerCount: 5, turnTimeLimit: 30 });
    });

    it('sends 0 when the timer is left off', async () => {
      renderCreateParty();
      fillForm();
      fireEvent.click(createButton());

      await waitFor(() => expect(apiClient.post).toHaveBeenCalled());
      expect(createdSettings().turnTimeLimit).toBe(0);
    });

    it('sends 120 for two minutes', async () => {
      renderCreateParty();
      fillForm();
      fireEvent.click(timerChoice('2 min'));
      fireEvent.click(createButton());

      await waitFor(() => expect(apiClient.post).toHaveBeenCalled());
      expect(createdSettings().turnTimeLimit).toBe(120);
    });
  });

  describe('Player Count Validation (README compliance)', () => {
    it('should validate player count is between 3-8 (game rule)', async () => {
      apiClient.post = vi.fn();

      renderCreateParty();
      // Test below minimum (< 3)
      fillForm({ playerCount: '2' });
      fireEvent.submit(createButton().closest('form'));

      await waitFor(() => {
        expect(screen.getByText(/must be between 3 and 8/i)).toBeInTheDocument();
      });

      expect(apiClient.post).not.toHaveBeenCalled();
    });

    it('should reject player count above maximum (> 8)', async () => {
      apiClient.post = vi.fn();

      renderCreateParty();
      fillForm({ playerCount: '9' });
      fireEvent.submit(createButton().closest('form'));

      await waitFor(() => {
        expect(screen.getByText(/must be between 3 and 8/i)).toBeInTheDocument();
      });

      expect(apiClient.post).not.toHaveBeenCalled();
    });

    it('should accept valid player count (3-8)', async () => {
      apiClient.post = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: { id: '1', name: 'Test Party' },
        },
      });

      renderCreateParty();
      fillForm({ playerCount: '5' });
      fireEvent.click(createButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalled();
      });
    });

    it('should require a party name', async () => {
      apiClient.post = vi.fn();

      renderCreateParty();
      fillForm({ name: '   ' });
      fireEvent.submit(createButton().closest('form'));

      await waitFor(() => {
        expect(screen.getByText(/party name is required/i)).toBeInTheDocument();
      });

      expect(apiClient.post).not.toHaveBeenCalled();
    });
  });

  describe('Form Submission', () => {
    it('should submit party creation with all settings', async () => {
      apiClient.post = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: { id: '1', name: 'Test Party' },
        },
      });

      renderCreateParty();
      fillForm({ name: 'My Party', playerCount: '5' });
      fireEvent.click(createButton());

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith(
          '/party',
          expect.objectContaining({
            name: 'My Party',
            visibility: 'public',
            settings: expect.objectContaining({
              playerCount: 5,
            }),
          })
        );
        expect(apiClient.post.mock.calls[0][1]).not.toHaveProperty('botIds');
      });
    });

    it('should navigate to party lobby on success', async () => {
      apiClient.post = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: { id: 'party-123', name: 'Test Party' },
        },
      });

      renderCreateParty();
      fillForm();
      fireEvent.click(createButton());

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/party/party-123');
      });
    });

    it('should show error on failed creation', async () => {
      apiClient.post = vi.fn().mockRejectedValue(new Error('Network down'));

      renderCreateParty();
      fillForm();
      fireEvent.click(createButton());

      await waitFor(() => {
        expect(screen.getByRole('alert')).toHaveTextContent(/failed to create party/i);
      });
      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('should disable submit while creating', async () => {
      apiClient.post = vi.fn(() => new Promise(() => {}));

      renderCreateParty();
      fillForm();
      const submitButton = createButton();
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(submitButton).toBeDisabled();
      });
    });
  });
});
