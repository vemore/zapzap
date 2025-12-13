import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { GoogleOAuthProvider } from '@react-oauth/google';
import { AuthProvider } from './contexts/AuthContext';
import Login from './components/Auth/Login';
import Register from './components/Auth/Register';
import ProtectedRoute from './components/Auth/ProtectedRoute';
import PartyList from './components/Party/PartyList';
import CreateParty from './components/Party/CreateParty';
import PartyLobby from './components/Party/PartyLobby';
import GameBoard from './components/Game/GameBoard';
import GameHistory from './components/History/GameHistory';
import GameDetails from './components/History/GameDetails';
import Statistics from './components/Stats/Statistics';
import AdminRoute from './components/Admin/AdminRoute';
import AdminLayout from './components/Admin/AdminLayout';
import UserList from './components/Admin/Users/UserList';
import AdminPartyList from './components/Admin/Parties/AdminPartyList';
import AdminStats from './components/Admin/Statistics/AdminStats';
import './App.css';

// Google OAuth Client ID from environment variable
const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID || '';

/**
 * Main App component with routing configuration
 */
function App() {
  // Wrap with GoogleOAuthProvider only if client ID is configured
  const content = (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          {/* Public routes */}
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />

          {/* Protected routes */}
          <Route
            path="/parties"
            element={
              <ProtectedRoute>
                <PartyList />
              </ProtectedRoute>
            }
          />
          <Route
            path="/create-party"
            element={
              <ProtectedRoute>
                <CreateParty />
              </ProtectedRoute>
            }
          />
          <Route
            path="/party/:partyId"
            element={
              <ProtectedRoute>
                <PartyLobby />
              </ProtectedRoute>
            }
          />
          <Route
            path="/game/:partyId"
            element={
              <ProtectedRoute>
                <GameBoard />
              </ProtectedRoute>
            }
          />
          <Route
            path="/history"
            element={
              <ProtectedRoute>
                <GameHistory />
              </ProtectedRoute>
            }
          />
          <Route
            path="/history/:partyId"
            element={
              <ProtectedRoute>
                <GameDetails />
              </ProtectedRoute>
            }
          />
          <Route
            path="/stats"
            element={
              <ProtectedRoute>
                <Statistics />
              </ProtectedRoute>
            }
          />

          {/* Admin routes */}
          <Route
            path="/admin"
            element={
              <AdminRoute>
                <AdminLayout />
              </AdminRoute>
            }
          >
            <Route index element={<Navigate to="/admin/users" replace />} />
            <Route path="users" element={<UserList />} />
            <Route path="parties" element={<AdminPartyList />} />
            <Route path="statistics" element={<AdminStats />} />
          </Route>

          {/* Root redirect - send to login page */}
          <Route path="/" element={<Navigate to="/login" replace />} />

          {/* Catch-all redirect */}
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );

  // Wrap with GoogleOAuthProvider if client ID is configured
  if (GOOGLE_CLIENT_ID) {
    return (
      <GoogleOAuthProvider clientId={GOOGLE_CLIENT_ID}>
        {content}
      </GoogleOAuthProvider>
    );
  }

  return content;
}

export default App;
