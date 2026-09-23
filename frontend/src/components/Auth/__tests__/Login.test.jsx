import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import Login from '../Login';
import { AuthProvider } from '../../../contexts/AuthContext';
import * as auth from '../../../services/auth';

// Mock the auth service (the AuthProvider reads it too)
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

// The form is in French: "Pseudo", "Mot de passe", "Se connecter".
function renderLogin() {
  return render(
    <BrowserRouter>
      <AuthProvider>
        <Login />
      </AuthProvider>
    </BrowserRouter>
  );
}

function fillAndSubmit({ username, password }) {
  if (username !== undefined) {
    fireEvent.change(screen.getByLabelText(/pseudo/i), { target: { value: username } });
  }
  if (password !== undefined) {
    fireEvent.change(screen.getByLabelText(/mot de passe/i), { target: { value: password } });
  }
  const submitButton = screen.getByRole('button', { name: /se connecter/i });
  fireEvent.click(submitButton);
  return submitButton;
}

describe('Phase 2: Login Component Tests', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  describe('Form Rendering', () => {
    it('should render login form with username and password fields', () => {
      renderLogin();

      expect(screen.getByLabelText(/pseudo/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/mot de passe/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /se connecter/i })).toBeInTheDocument();
    });

    it('should render link to register page', () => {
      renderLogin();

      const registerLink = screen.getByRole('link', { name: /s'inscrire/i });
      expect(registerLink).toHaveAttribute('href', '/register');
    });

    it('should have password field with type password', () => {
      renderLogin();

      const passwordField = screen.getByLabelText(/mot de passe/i);
      expect(passwordField).toHaveAttribute('type', 'password');
    });
  });

  describe('Form Submission', () => {
    it('should call login API with username and password on submit', async () => {
      vi.mocked(auth.login).mockResolvedValue({
        success: true,
        user: { id: '1', username: 'testuser' },
      });

      renderLogin();
      fillAndSubmit({ username: 'testuser', password: 'password123' });

      await waitFor(() => {
        expect(auth.login).toHaveBeenCalledWith('testuser', 'password123');
      });
    });

    it('should redirect to party list on successful login', async () => {
      vi.mocked(auth.login).mockResolvedValue({
        success: true,
        user: { id: '1', username: 'testuser' },
      });

      renderLogin();
      fillAndSubmit({ username: 'testuser', password: 'password123' });

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/parties');
      });
    });

    it('should display error message on failed login', async () => {
      vi.mocked(auth.login).mockRejectedValue(new Error('Invalid credentials'));

      renderLogin();
      fillAndSubmit({ username: 'testuser', password: 'wrongpass' });

      await waitFor(() => {
        expect(screen.getByRole('alert')).toHaveTextContent(/invalid credentials/i);
      });
      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('should disable submit button while logging in', async () => {
      vi.mocked(auth.login).mockImplementation(() => new Promise(() => {}));

      renderLogin();
      const submitButton = fillAndSubmit({ username: 'testuser', password: 'password123' });

      await waitFor(() => {
        expect(submitButton).toBeDisabled();
      });
    });
  });

  describe('Form Validation', () => {
    it('should prevent submission with empty username', async () => {
      renderLogin();
      fillAndSubmit({ password: 'password123' });

      await waitFor(() => {
        expect(auth.login).not.toHaveBeenCalled();
      });
    });

    it('should prevent submission with empty password', async () => {
      renderLogin();
      fillAndSubmit({ username: 'testuser' });

      await waitFor(() => {
        expect(auth.login).not.toHaveBeenCalled();
      });
    });
  });
});
