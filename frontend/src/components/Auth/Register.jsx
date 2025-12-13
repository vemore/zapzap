import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Zap, Loader } from 'lucide-react';
import { register as registerUser, validateUsername, validatePassword } from '../../services/auth';
import { useAuth } from '../../contexts/AuthContext';
import GoogleLoginButton from './GoogleLoginButton';

// Check if Google OAuth is configured
const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID || '';

function Register() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [usernameError, setUsernameError] = useState('');
  const [passwordError, setPasswordError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const { setUser } = useAuth();

  // Validate username on change (with debounce effect)
  useEffect(() => {
    if (username.length === 0) {
      setUsernameError('');
      return;
    }
    const validation = validateUsername(username);
    setUsernameError(validation.valid ? '' : validation.message);
  }, [username]);

  // Validate password on change
  useEffect(() => {
    if (password.length === 0) {
      setPasswordError('');
      return;
    }
    const validation = validatePassword(password);
    setPasswordError(validation.valid ? '' : validation.message);
  }, [password]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    // Final validation before submit
    const usernameValidation = validateUsername(username);
    const passwordValidation = validatePassword(password);

    if (!usernameValidation.valid) {
      setUsernameError(usernameValidation.message);
      return;
    }

    if (!passwordValidation.valid) {
      setPasswordError(passwordValidation.message);
      return;
    }

    setLoading(true);

    try {
      const result = await registerUser(username, password);
      setUser(result.user);  // Update auth context with user data
      navigate('/parties');
    } catch (err) {
      setError(err.message || 'Inscription échouée');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700">
          {/* Header with icon */}
          <div className="flex items-center justify-center mb-8">
            <Zap className="w-8 h-8 text-amber-400 mr-2" />
            <h1 className="text-3xl font-bold text-white">ZapZap</h1>
          </div>

          <h2 className="text-xl font-semibold text-center text-gray-200 mb-6">
            Créer un compte
          </h2>

          {/* Google Login Button */}
          {GOOGLE_CLIENT_ID && (
            <>
              <GoogleLoginButton onError={setError} />
              <div className="flex items-center my-4">
                <div className="flex-1 border-t border-slate-600"></div>
                <span className="px-4 text-sm text-gray-400">ou</span>
                <div className="flex-1 border-t border-slate-600"></div>
              </div>
            </>
          )}

          {error && (
            <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg mb-4" role="alert">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="username" className="block text-sm font-medium text-gray-300 mb-2">
                Pseudo
              </label>
              <input
                id="username"
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="Lettres, chiffres, tirets et underscores"
                disabled={loading}
                autoComplete="username"
                className={`w-full px-4 py-2 bg-slate-700 border rounded-lg text-white placeholder-gray-400 focus:outline-none transition-colors disabled:opacity-60 disabled:cursor-not-allowed ${
                  usernameError ? 'border-red-500 focus:border-red-400' : 'border-slate-600 focus:border-amber-400'
                }`}
              />
              {usernameError && (
                <p className="mt-1 text-sm text-red-400">{usernameError}</p>
              )}
              <p className="mt-1 text-xs text-gray-500">3-30 caractères</p>
            </div>

            <div>
              <label htmlFor="password" className="block text-sm font-medium text-gray-300 mb-2">
                Mot de passe
              </label>
              <input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Minimum 6 caractères"
                disabled={loading}
                autoComplete="new-password"
                className={`w-full px-4 py-2 bg-slate-700 border rounded-lg text-white placeholder-gray-400 focus:outline-none transition-colors disabled:opacity-60 disabled:cursor-not-allowed ${
                  passwordError ? 'border-red-500 focus:border-red-400' : 'border-slate-600 focus:border-amber-400'
                }`}
              />
              {passwordError && (
                <p className="mt-1 text-sm text-red-400">{passwordError}</p>
              )}
              <p className="mt-1 text-xs text-gray-500">6-100 caractères</p>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-amber-500 hover:bg-amber-600 disabled:bg-gray-600 text-white font-semibold py-2 rounded-lg transition-colors disabled:cursor-not-allowed flex items-center justify-center"
            >
              {loading ? (
                <>
                  <Loader className="w-5 h-5 mr-2 animate-spin" />
                  Inscription...
                </>
              ) : (
                "S'inscrire"
              )}
            </button>
          </form>

          <p className="mt-6 text-center text-gray-400">
            Déjà un compte ?{' '}
            <Link to="/login" className="text-amber-400 hover:text-amber-300 font-medium transition-colors">
              Se connecter
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}

export default Register;
