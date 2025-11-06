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

describe('Phase 3: CreateParty Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockNavigate.mockClear();
  });

  describe('Form Rendering', () => {
    it('should render create party form with all fields', () => {
      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      expect(screen.getByLabelText(/party name/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/player count/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/hand size/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /create/i })).toBeInTheDocument();
    });

    it('should have visibility toggle (public/private)', () => {
      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      expect(screen.getByLabelText(/visibility/i)).toBeInTheDocument();
    });
  });

  describe('Player Count Validation (README compliance)', () => {
    it('should validate player count is between 3-8 (game rule)', async () => {
      apiClient.post = vi.fn();

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const form = screen.getByRole('button', { name: /create/i }).closest('form');
      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);

      // Fill in required fields first
      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(handSizeInput, { target: { value: '7' } });

      // Test below minimum (< 3)
      fireEvent.change(playerCountInput, { target: { value: '2' } });

      // Submit the form
      fireEvent.submit(form);

      await waitFor(() => {
        expect(screen.getByText(/must be between 3 and 8/i)).toBeInTheDocument();
      });

      expect(apiClient.post).not.toHaveBeenCalled();
    });

    it('should reject player count above maximum (> 8)', async () => {
      apiClient.post = vi.fn();

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const form = screen.getByRole('button', { name: /create/i }).closest('form');
      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(handSizeInput, { target: { value: '7' } });
      fireEvent.change(playerCountInput, { target: { value: '9' } });

      fireEvent.submit(form);

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

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);
      const submitButton = screen.getByRole('button', { name: /create/i });

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });
      fireEvent.change(handSizeInput, { target: { value: '7' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalled();
      });
    });
  });

  describe('Hand Size Validation (README compliance)', () => {
    it('should validate hand size is between 5-7 (game rule)', async () => {
      apiClient.post = vi.fn();

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const form = screen.getByRole('button', { name: /create/i }).closest('form');
      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });

      // Test below minimum (< 5)
      fireEvent.change(handSizeInput, { target: { value: '4' } });

      fireEvent.submit(form);

      await waitFor(() => {
        expect(screen.getByText(/must be between 5 and 7/i)).toBeInTheDocument();
      });

      expect(apiClient.post).not.toHaveBeenCalled();
    });

    it('should reject hand size above maximum (> 7)', async () => {
      apiClient.post = vi.fn();

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const form = screen.getByRole('button', { name: /create/i }).closest('form');
      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });
      fireEvent.change(handSizeInput, { target: { value: '8' } });

      fireEvent.submit(form);

      await waitFor(() => {
        expect(screen.getByText(/must be between 5 and 7/i)).toBeInTheDocument();
      });

      expect(apiClient.post).not.toHaveBeenCalled();
    });

    it('should accept valid hand size (5-7)', async () => {
      apiClient.post = vi.fn().mockResolvedValue({
        data: {
          success: true,
          party: { id: '1', name: 'Test Party' },
        },
      });

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);
      const submitButton = screen.getByRole('button', { name: /create/i });

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });
      fireEvent.change(handSizeInput, { target: { value: '6' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalled();
      });
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

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);
      const submitButton = screen.getByRole('button', { name: /create/i });

      fireEvent.change(nameInput, { target: { value: 'My Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });
      fireEvent.change(handSizeInput, { target: { value: '7' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(apiClient.post).toHaveBeenCalledWith(
          '/party',
          expect.objectContaining({
            name: 'My Party',
            settings: expect.objectContaining({
              playerCount: 5,
              handSize: 7,
            }),
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

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);
      const submitButton = screen.getByRole('button', { name: /create/i });

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });
      fireEvent.change(handSizeInput, { target: { value: '7' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/party/party-123');
      });
    });

    it('should show error on failed creation', async () => {
      apiClient.post = vi.fn().mockRejectedValue(new Error('Failed to create party'));

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);
      const submitButton = screen.getByRole('button', { name: /create/i });

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });
      fireEvent.change(handSizeInput, { target: { value: '7' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText(/failed to create party/i)).toBeInTheDocument();
      });
    });

    it('should disable submit while creating', async () => {
      apiClient.post = vi.fn(() => new Promise(resolve => setTimeout(() => resolve({ data: { success: true } }), 100)));

      render(
        <BrowserRouter>
          <CreateParty />
        </BrowserRouter>
      );

      const nameInput = screen.getByLabelText(/party name/i);
      const playerCountInput = screen.getByLabelText(/player count/i);
      const handSizeInput = screen.getByLabelText(/hand size/i);
      const submitButton = screen.getByRole('button', { name: /create/i });

      fireEvent.change(nameInput, { target: { value: 'Test Party' } });
      fireEvent.change(playerCountInput, { target: { value: '5' } });
      fireEvent.change(handSizeInput, { target: { value: '7' } });
      fireEvent.click(submitButton);

      expect(submitButton).toBeDisabled();
    });
  });
});
