import { GoogleLogin } from '@react-oauth/google';
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { loginWithGoogle } from '../../services/auth';
import { useAuth } from '../../contexts/AuthContext';

function GoogleLoginButton({ onError }) {
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const { setUser } = useAuth();

  const handleSuccess = async (credentialResponse) => {
    setLoading(true);
    try {
      const result = await loginWithGoogle(credentialResponse.credential);
      setUser(result.user);
      navigate('/parties');
    } catch (error) {
      console.error('Google login error:', error);
      if (onError) {
        onError(error.message || 'Connexion Google échouée');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleError = () => {
    if (onError) {
      onError('Connexion Google annulée ou échouée');
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center py-2">
        <div className="w-6 h-6 border-2 border-gray-400 border-t-amber-400 rounded-full animate-spin"></div>
        <span className="ml-2 text-gray-400">Connexion en cours...</span>
      </div>
    );
  }

  return (
    <div className="flex justify-center">
      <GoogleLogin
        onSuccess={handleSuccess}
        onError={handleError}
        theme="filled_black"
        size="large"
        text="continue_with"
        shape="rectangular"
        locale="fr"
        useOneTap={false}
      />
    </div>
  );
}

export default GoogleLoginButton;
