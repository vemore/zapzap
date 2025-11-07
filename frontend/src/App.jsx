import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './contexts/AuthContext';
import Login from './components/Auth/Login';
import Register from './components/Auth/Register';
import ProtectedRoute from './components/Auth/ProtectedRoute';
import PartyList from './components/Party/PartyList';
import PartyLobby from './components/Party/PartyLobby';
import GameBoard from './components/Game/GameBoard';
import './App.css';

/**
 * Main App component with routing configuration
 */
function App() {
  return (
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

          {/* Root redirect - send to login page */}
          <Route path="/" element={<Navigate to="/login" replace />} />

          {/* Catch-all redirect */}
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}

export default App;
