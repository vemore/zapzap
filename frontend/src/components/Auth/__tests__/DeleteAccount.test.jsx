import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import DeleteAccount from '../DeleteAccount';
import ProtectedRoute from '../ProtectedRoute';
import { AuthProvider } from '../../../contexts/AuthContext';
import * as auth from '../../../services/auth';

vi.mock('../../../services/auth');

function LoginProbe() {
  return <div>Login Page</div>;
}

// The app's own route: /account/delete behind ProtectedRoute, as Play links to it
function renderAt(path = '/account/delete') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <AuthProvider>
        <Routes>
          <Route
            path="/account/delete"
            element={
              <ProtectedRoute>
                <DeleteAccount />
              </ProtectedRoute>
            }
          />
          <Route path="/login" element={<LoginProbe />} />
        </Routes>
      </AuthProvider>
    </MemoryRouter>
  );
}

describe('DeleteAccount (/account/delete)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(auth.isAuthenticated).mockReturnValue(true);
    vi.mocked(auth.getCurrentUser).mockReturnValue({ id: 'u1', username: 'alice' });
  });

  it('signed out, the page sends the visitor to the login', () => {
    vi.mocked(auth.isAuthenticated).mockReturnValue(false);
    vi.mocked(auth.getCurrentUser).mockReturnValue(null);
    renderAt();
    expect(screen.getByText('Login Page')).toBeInTheDocument();
  });

  it('confirms with the password, deletes, then returns to the login', async () => {
    vi.mocked(auth.deleteAccount).mockResolvedValue({ success: true, deletedUserId: 'u1' });
    renderAt();

    expect(screen.getByRole('heading', { name: /supprimer mon compte/i })).toBeInTheDocument();
    expect(screen.getByText(/joueur supprimé/i)).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(/mot de passe/i), { target: { value: 'secret' } });
    fireEvent.click(screen.getByRole('button', { name: /supprimer définitivement/i }));

    await waitFor(() => expect(screen.getByText('Login Page')).toBeInTheDocument());
    expect(auth.deleteAccount).toHaveBeenCalledWith({ password: 'secret' });
  });

  it('a wrong password stays on the page and says so', async () => {
    const refused = Object.assign(new Error('Invalid password'), { code: 'INVALID_PASSWORD' });
    vi.mocked(auth.deleteAccount).mockRejectedValue(refused);
    renderAt();

    fireEvent.change(screen.getByLabelText(/mot de passe/i), { target: { value: 'wrong' } });
    fireEvent.click(screen.getByRole('button', { name: /supprimer définitivement/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Mot de passe incorrect.');
    expect(screen.queryByText('Login Page')).not.toBeInTheDocument();
  });

  it('a seat in a game in progress is explained', async () => {
    const refused = Object.assign(new Error('Leave first'), { code: 'ACTIVE_PARTY' });
    vi.mocked(auth.deleteAccount).mockRejectedValue(refused);
    renderAt();

    fireEvent.change(screen.getByLabelText(/mot de passe/i), { target: { value: 'secret' } });
    fireEvent.click(screen.getByRole('button', { name: /supprimer définitivement/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/quitte-la ou termine-la/);
  });

  it('an empty password is not sent', () => {
    renderAt();
    fireEvent.click(screen.getByRole('button', { name: /supprimer définitivement/i }));
    expect(auth.deleteAccount).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toBeInTheDocument();
  });

  it('a Google account gets no password field', () => {
    vi.mocked(auth.getCurrentUser).mockReturnValue({
      id: 'u2',
      username: 'ada',
      isGoogleUser: true,
    });
    renderAt();
    expect(screen.queryByLabelText(/mot de passe/i)).not.toBeInTheDocument();
    expect(screen.getByText(/confirme avec ton compte google/i)).toBeInTheDocument();
  });
});
