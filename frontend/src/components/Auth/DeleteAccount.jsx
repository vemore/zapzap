import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { GoogleLogin } from '@react-oauth/google';
import { Zap, Loader, Trash2 } from 'lucide-react';
import { deleteAccount } from '../../services/auth';
import { useAuth } from '../../contexts/AuthContext';

// Google re-authentication needs the GoogleOAuthProvider App mounts when this is set
const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID || '';

// The backend's refusal codes (DELETE /api/auth/me), in the player's words
const ERRORS = {
  INVALID_PASSWORD: 'Mot de passe incorrect.',
  MISSING_CONFIRMATION: 'Entre ton mot de passe pour confirmer.',
  GOOGLE_AUTH_FAILED: 'Google n’a pas confirmé ce compte. Réessaie avec le même compte Google.',
  ACTIVE_PARTY:
    'Tu es encore dans une partie en attente ou en cours : quitte-la ou termine-la d’abord.',
  LAST_ADMIN: 'Tu es le seul administrateur : ton compte ne peut pas être supprimé.',
};

/**
 * Delete my account — also the page Google Play links to for deleting an account from the
 * web (/account/delete; signed out, ProtectedRoute sends the visitor to the login first
 * and the login brings them back here).
 */
function DeleteAccount() {
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const { user, setUser } = useAuth();
  const isGoogleUser = !!user?.isGoogleUser;

  const confirm = async (confirmation) => {
    setError('');
    setLoading(true);
    try {
      await deleteAccount(confirmation);
      setUser(null);
      navigate('/login', { replace: true, state: { accountDeleted: true } });
    } catch (err) {
      setError(ERRORS[err.code] || err.message || 'Suppression du compte échouée');
      setLoading(false);
    }
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!password) {
      setError(ERRORS.MISSING_CONFIRMATION);
      return;
    }
    confirm({ password });
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700">
          <div className="flex items-center justify-center mb-8">
            <Zap className="w-8 h-8 text-amber-400 mr-2" />
            <h1 className="text-3xl font-bold text-white">ZapZap</h1>
          </div>

          <h2 className="text-xl font-semibold text-center text-gray-200 mb-4">
            Supprimer mon compte
          </h2>

          <div className="text-sm text-gray-300 space-y-2 mb-6">
            <p>
              Le compte <span className="font-semibold text-white">{user?.username}</span> sera
              supprimé définitivement : ton pseudo, ton mot de passe et ton lien Google.
            </p>
            <p>
              Les parties terminées restent dans l’historique des autres joueurs, où tu
              apparais comme « Joueur supprimé ». Cette action est irréversible.
            </p>
          </div>

          {error && (
            <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg mb-4" role="alert">
              {error}
            </div>
          )}

          {isGoogleUser ? (
            <div className="space-y-3">
              <p className="text-sm text-gray-300">Confirme avec ton compte Google :</p>
              {loading ? (
                <div className="flex justify-center items-center py-2 text-gray-400">
                  <Loader className="w-5 h-5 mr-2 animate-spin" />
                  Suppression...
                </div>
              ) : GOOGLE_CLIENT_ID ? (
                <div className="flex justify-center">
                  <GoogleLogin
                    onSuccess={(response) => confirm({ credential: response.credential })}
                    onError={() => setError(ERRORS.GOOGLE_AUTH_FAILED)}
                    theme="filled_black"
                    text="continue_with"
                    locale="fr"
                    useOneTap={false}
                  />
                </div>
              ) : (
                <p className="text-sm text-red-300">
                  La connexion Google n’est pas configurée sur ce serveur.
                </p>
              )}
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label htmlFor="delete-password" className="block text-sm font-medium text-gray-300 mb-2">
                  Mot de passe
                </label>
                <input
                  id="delete-password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  disabled={loading}
                  autoComplete="current-password"
                  className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:border-red-400 transition-colors disabled:opacity-60"
                />
              </div>
              <button
                type="submit"
                disabled={loading}
                className="w-full bg-red-600 hover:bg-red-700 disabled:bg-gray-600 text-white font-semibold py-2 rounded-lg transition-colors flex items-center justify-center"
              >
                {loading ? (
                  <>
                    <Loader className="w-5 h-5 mr-2 animate-spin" />
                    Suppression...
                  </>
                ) : (
                  <>
                    <Trash2 className="w-5 h-5 mr-2" />
                    Supprimer définitivement
                  </>
                )}
              </button>
            </form>
          )}

          <p className="mt-6 text-center text-sm">
            <Link to="/parties" className="text-amber-400 hover:text-amber-300">
              Annuler
            </Link>
            <span className="text-gray-500"> · </span>
            <a href="/privacy" className="text-gray-400 hover:text-gray-300">
              Politique de confidentialité
            </a>
          </p>
        </div>
      </div>
    </div>
  );
}

export default DeleteAccount;
