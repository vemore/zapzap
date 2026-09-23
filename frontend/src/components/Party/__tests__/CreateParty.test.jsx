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
    // On mount the form lists the bots a slot can take
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
            botIds: [],
          })
        );
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
