import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import Register from '../Register';
import * as auth from '../../../services/auth';

// Mock the auth service
vi.mock('../../../services/auth');

// Mock useNavigate
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

describe('Phase 2: Register Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockNavigate.mockClear();
  });

  describe('Form Rendering', () => {
    it('should render registration form with username and password fields', () => {
      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      expect(screen.getByLabelText(/username/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/^password$/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /register/i })).toBeInTheDocument();
    });

    it('should render link to login page', () => {
      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const loginLink = screen.getByText(/login/i);
      expect(loginLink).toBeInTheDocument();
    });

    it('should have password fields with type password', () => {
      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const passwordFields = screen.getAllByLabelText(/password/i);
      passwordFields.forEach(field => {
        expect(field).toHaveAttribute('type', 'password');
      });
    });
  });

  describe('Form Validation', () => {
    it('should validate username is at least 3 characters', async () => {
      auth.register = vi.fn();

      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/^password$/i);
      const submitButton = screen.getByRole('button', { name: /register/i });

      fireEvent.change(usernameInput, { target: { value: 'ab' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText(/username must be at least 3 characters/i)).toBeInTheDocument();
      });

      expect(auth.register).not.toHaveBeenCalled();
    });

    it('should validate password is at least 6 characters', async () => {
      auth.register = vi.fn();

      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/^password$/i);
      const submitButton = screen.getByRole('button', { name: /register/i });

      fireEvent.change(usernameInput, { target: { value: 'testuser' } });
      fireEvent.change(passwordInput, { target: { value: '12345' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText(/password must be at least 6 characters/i)).toBeInTheDocument();
      });

      expect(auth.register).not.toHaveBeenCalled();
    });

    it('should show error for empty fields', async () => {
      auth.register = vi.fn();

      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const submitButton = screen.getByRole('button', { name: /register/i });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(auth.register).not.toHaveBeenCalled();
      });
    });
  });

  describe('Form Submission', () => {
    it('should call register API with valid credentials', async () => {
      auth.register = vi.fn().mockResolvedValue({
        success: true,
        user: { id: '1', username: 'newuser' },
      });

      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/^password$/i);
      const submitButton = screen.getByRole('button', { name: /register/i });

      fireEvent.change(usernameInput, { target: { value: 'newuser' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(auth.register).toHaveBeenCalledWith('newuser', 'password123');
      });
    });

    it('should redirect to party list on successful registration', async () => {
      auth.register = vi.fn().mockResolvedValue({
        success: true,
        user: { id: '1', username: 'newuser' },
      });

      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/^password$/i);
      const submitButton = screen.getByRole('button', { name: /register/i });

      fireEvent.change(usernameInput, { target: { value: 'newuser' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/parties');
      });
    });

    it('should display error message on failed registration', async () => {
      auth.register = vi.fn().mockRejectedValue(new Error('Username already exists'));

      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/^password$/i);
      const submitButton = screen.getByRole('button', { name: /register/i });

      fireEvent.change(usernameInput, { target: { value: 'existinguser' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText(/username already exists/i)).toBeInTheDocument();
      });
    });

    it('should disable submit button while registering', async () => {
      auth.register = vi.fn(() => new Promise(resolve => setTimeout(() => resolve({ success: true }), 100)));

      render(
        <BrowserRouter>
          <Register />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/^password$/i);
      const submitButton = screen.getByRole('button', { name: /register/i });

      fireEvent.change(usernameInput, { target: { value: 'newuser' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      expect(submitButton).toBeDisabled();
    });
  });
});
