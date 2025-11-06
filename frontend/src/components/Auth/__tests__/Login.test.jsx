import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import Login from '../Login';
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

describe('Phase 2: Login Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockNavigate.mockClear();
  });

  describe('Form Rendering', () => {
    it('should render login form with username and password fields', () => {
      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      expect(screen.getByLabelText(/username/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /login/i })).toBeInTheDocument();
    });

    it('should render link to register page', () => {
      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const registerLink = screen.getByText(/register/i);
      expect(registerLink).toBeInTheDocument();
    });

    it('should have password field with type password', () => {
      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const passwordField = screen.getByLabelText(/password/i);
      expect(passwordField).toHaveAttribute('type', 'password');
    });
  });

  describe('Form Submission', () => {
    it('should call login API with username and password on submit', async () => {
      auth.login = vi.fn().mockResolvedValue({
        success: true,
        user: { id: '1', username: 'testuser' },
      });

      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      fireEvent.change(usernameInput, { target: { value: 'testuser' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(auth.login).toHaveBeenCalledWith('testuser', 'password123');
      });
    });

    it('should redirect to party list on successful login', async () => {
      auth.login = vi.fn().mockResolvedValue({
        success: true,
        user: { id: '1', username: 'testuser' },
      });

      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      fireEvent.change(usernameInput, { target: { value: 'testuser' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/parties');
      });
    });

    it('should display error message on failed login', async () => {
      auth.login = vi.fn().mockRejectedValue(new Error('Invalid credentials'));

      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      fireEvent.change(usernameInput, { target: { value: 'testuser' } });
      fireEvent.change(passwordInput, { target: { value: 'wrongpass' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText(/invalid credentials/i)).toBeInTheDocument();
      });
    });

    it('should disable submit button while logging in', async () => {
      auth.login = vi.fn(() => new Promise(resolve => setTimeout(() => resolve({ success: true }), 100)));

      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      fireEvent.change(usernameInput, { target: { value: 'testuser' } });
      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      expect(submitButton).toBeDisabled();
    });
  });

  describe('Form Validation', () => {
    it('should prevent submission with empty username', async () => {
      auth.login = vi.fn();

      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      fireEvent.change(passwordInput, { target: { value: 'password123' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(auth.login).not.toHaveBeenCalled();
      });
    });

    it('should prevent submission with empty password', async () => {
      auth.login = vi.fn();

      render(
        <BrowserRouter>
          <Login />
        </BrowserRouter>
      );

      const usernameInput = screen.getByLabelText(/username/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      fireEvent.change(usernameInput, { target: { value: 'testuser' } });
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(auth.login).not.toHaveBeenCalled();
      });
    });
  });
});
