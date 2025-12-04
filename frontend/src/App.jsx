import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
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
