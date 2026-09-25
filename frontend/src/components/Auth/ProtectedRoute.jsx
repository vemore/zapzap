import { Navigate, useLocation } from 'react-router-dom';
import { isAuthenticated } from '../../services/auth';

// A signed-out visitor goes to the login, which brings them back here (`from`): a link
// to a protected page, such as /account/delete, works from outside the app.
function ProtectedRoute({ children }) {
  const location = useLocation();
  if (!isAuthenticated()) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  return children;
}

export default ProtectedRoute;
