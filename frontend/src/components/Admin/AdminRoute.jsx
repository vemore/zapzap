import { Navigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';

/**
 * AdminRoute - Protected route component that requires admin privileges
 * Redirects to /parties if user is not authenticated or not an admin
 */
function AdminRoute({ children }) {
  const { user, isAuthenticated, loading } = useAuth();

  // Show loading state while checking authentication
  if (loading) {
    return (
      <div className="min-h-screen bg-slate-900 flex items-center justify-center">
        <div className="text-amber-400">Loading...</div>
      </div>
    );
  }

  // Redirect to login if not authenticated
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  // Redirect to parties if not admin
  if (!user?.isAdmin) {
    return <Navigate to="/parties" replace />;
  }

  return children;
}

export default AdminRoute;
