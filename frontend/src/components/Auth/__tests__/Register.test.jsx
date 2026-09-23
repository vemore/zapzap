import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import Register from '../Register';
import { AuthProvider } from '../../../contexts/AuthContext';
import * as auth from '../../../services/auth';

// Mock the network side of the auth service; the form validators stay real,
// since they are what the validation tests exercise.
vi.mock('../../../services/auth', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    register: vi.fn(),
    login: vi.fn(),
    logout: vi.fn(),
    getCurrentUser: vi.fn(() => null),
    isAuthenticated: vi.fn(() => false),
  };
});

// Mock useNavigate
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// The form is in French: "Pseudo", "Mot de passe", "S'inscrire".
function renderRegister() {
  return render(
    <BrowserRouter>
      <AuthProvider>
        <Register />
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
  const submitButton = screen.getByRole('button', { name: /s'inscrire/i });
  fireEvent.click(submitButton);
  return submitButton;
}

describe('Phase 2: Register Component Tests', () => {
  beforeEach(() => {
    vi.mocked(auth.register).mockReset();
    mockNavigate.mockReset();
  });

  describe('Form Rendering', () => {
    it('should render registration form with username and password fields', () => {
      renderRegister();

      expect(screen.getByLabelText(/pseudo/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/mot de passe/i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /s'inscrire/i })).toBeInTheDocument();
    });

    it('should render link to login page', () => {
      renderRegister();

      const loginLink = screen.getByRole('link', { name: /se connecter/i });
      expect(loginLink).toHaveAttribute('href', '/login');
    });

    it('should have password fields with type password', () => {
      renderRegister();

      const passwordFields = screen.getAllByLabelText(/mot de passe/i);
      expect(passwordFields.length).toBeGreaterThan(0);
      passwordFields.forEach(field => {
        expect(field).toHaveAttribute('type', 'password');
      });
    });
  });

  describe('Form Validation', () => {
    it('should validate username is at least 3 characters', async () => {
      renderRegister();
      fillAndSubmit({ username: 'ab', password: 'password123' });

      await waitFor(() => {
        expect(screen.getByText(/le pseudo doit contenir au moins 3 caractères/i)).toBeInTheDocument();
      });

      expect(auth.register).not.toHaveBeenCalled();
    });

    it('should validate password is at least 6 characters', async () => {
      renderRegister();
      fillAndSubmit({ username: 'testuser', password: '12345' });

      await waitFor(() => {
        expect(screen.getByText(/le mot de passe doit contenir au moins 6 caractères/i)).toBeInTheDocument();
      });

      expect(auth.register).not.toHaveBeenCalled();
    });

    it('should show error for empty fields', async () => {
      renderRegister();
      fillAndSubmit({});

      await waitFor(() => {
        expect(screen.getByText(/le pseudo est requis/i)).toBeInTheDocument();
      });
      expect(auth.register).not.toHaveBeenCalled();
    });
  });

  describe('Form Submission', () => {
    it('should call register API with valid credentials', async () => {
      vi.mocked(auth.register).mockResolvedValue({
        success: true,
        user: { id: '1', username: 'newuser' },
      });

      renderRegister();
      fillAndSubmit({ username: 'newuser', password: 'password123' });

      await waitFor(() => {
        expect(auth.register).toHaveBeenCalledWith('newuser', 'password123');
      });
    });

    it('should redirect to party list on successful registration', async () => {
      vi.mocked(auth.register).mockResolvedValue({
        success: true,
        user: { id: '1', username: 'newuser' },
      });

      renderRegister();
      fillAndSubmit({ username: 'newuser', password: 'password123' });

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/parties');
      });
    });

    it('should display error message on failed registration', async () => {
      vi.mocked(auth.register).mockRejectedValue(new Error('Username already exists'));

      renderRegister();
      fillAndSubmit({ username: 'existinguser', password: 'password123' });

      await waitFor(() => {
        expect(screen.getByRole('alert')).toHaveTextContent(/username already exists/i);
      });
      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('should disable submit button while registering', async () => {
      vi.mocked(auth.register).mockImplementation(() => new Promise(() => {}));

      renderRegister();
      const submitButton = fillAndSubmit({ username: 'newuser', password: 'password123' });

      await waitFor(() => {
        expect(submitButton).toBeDisabled();
      });
    });
  });
});
