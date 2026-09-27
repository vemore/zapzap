import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BrowserRouter, MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
import ProtectedRoute from '../ProtectedRoute';
import Login from '../Login';
import { AuthProvider } from '../../../contexts/AuthContext';
import * as auth from '../../../services/auth';

// Mock the auth service
vi.mock('../../../services/auth');

describe('Phase 2: ProtectedRoute Component Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Authentication Check', () => {
    it('should render children when user is authenticated', () => {
      vi.mocked(auth.isAuthenticated).mockReturnValue(true);

      render(
        <BrowserRouter>
          <Routes>
            <Route
              path="/"
              element={
                <ProtectedRoute>
                  <div>Protected Content</div>
                </ProtectedRoute>
              }
            />
          </Routes>
        </BrowserRouter>
      );

      expect(screen.getByText('Protected Content')).toBeInTheDocument();
    });

    it('should redirect to login when user is not authenticated', () => {
      vi.mocked(auth.isAuthenticated).mockReturnValue(false);

      render(
        <BrowserRouter>
          <Routes>
            <Route
              path="/"
              element={
                <ProtectedRoute>
                  <div>Protected Content</div>
                </ProtectedRoute>
              }
            />
            <Route path="/login" element={<div>Login Page</div>} />
          </Routes>
        </BrowserRouter>
      );

      expect(screen.queryByText('Protected Content')).not.toBeInTheDocument();
      expect(screen.getByText('Login Page')).toBeInTheDocument();
    });

    it('should not render protected content when logged out', () => {
      vi.mocked(auth.isAuthenticated).mockReturnValue(false);

      render(
        <BrowserRouter>
          <Routes>
            <Route
              path="/"
              element={
                <ProtectedRoute>
                  <div>Protected Content</div>
                </ProtectedRoute>
              }
            />
            <Route path="/login" element={<div>Login Page</div>} />
          </Routes>
        </BrowserRouter>
      );

      expect(screen.queryByText('Protected Content')).not.toBeInTheDocument();
    });
  });

  describe('Return after login', () => {
    // Shows where the router is, query string included
    function Where() {
      const location = useLocation();
      return <div>At {`${location.pathname}${location.search}${location.hash}`}</div>;
    }

    it('keeps the query string and the hash in the redirect to login', () => {
      vi.mocked(auth.isAuthenticated).mockReturnValue(false);
      function LoginState() {
        return <div>From {useLocation().state?.from}</div>;
      }

      render(
        <MemoryRouter initialEntries={['/account/delete?lang=en#confirm']}>
          <Routes>
            <Route
              path="/account/delete"
              element={
                <ProtectedRoute>
                  <Where />
                </ProtectedRoute>
              }
            />
            <Route path="/login" element={<LoginState />} />
          </Routes>
        </MemoryRouter>
      );

      expect(screen.getByText('From /account/delete?lang=en#confirm')).toBeInTheDocument();
    });

    it('brings the visitor back to the page and its query string once signed in', async () => {
      let signedIn = false;
      vi.mocked(auth.isAuthenticated).mockImplementation(() => signedIn);
      vi.mocked(auth.login).mockImplementation(async () => {
        signedIn = true;
        return { success: true, user: { id: '1', username: 'testuser' } };
      });

      render(
        <MemoryRouter initialEntries={['/account/delete?lang=en']}>
          <AuthProvider>
            <Routes>
              <Route
                path="/account/delete"
                element={
                  <ProtectedRoute>
                    <Where />
                  </ProtectedRoute>
                }
              />
              <Route path="/login" element={<Login />} />
            </Routes>
          </AuthProvider>
        </MemoryRouter>
      );

      fireEvent.change(screen.getByLabelText(/pseudo/i), { target: { value: 'testuser' } });
      fireEvent.change(screen.getByLabelText(/mot de passe/i), {
        target: { value: 'password123' },
      });
      fireEvent.click(screen.getByRole('button', { name: /se connecter/i }));

      expect(await screen.findByText('At /account/delete?lang=en')).toBeInTheDocument();
    });
  });
});
