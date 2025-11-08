import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Dice6, LogOut, Play, ArrowLeft, Users, Loader, Crown, Settings, Bot } from 'lucide-react';
import { apiClient } from '../../services/api';
import { useAuth } from '../../contexts/AuthContext';

function PartyLobby() {
  const { partyId } = useParams();
  const [party, setParty] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const navigate = useNavigate();
  const { user, logout } = useAuth();

  useEffect(() => {
    fetchPartyDetails();
    // TODO: Set up SSE for real-time updates
  }, [partyId]);

  const fetchPartyDetails = async () => {
    try {
      const response = await apiClient.get(`/party/${partyId}`);
      setParty(response.data.party);
      setError('');
    } catch (err) {
      setError('Failed to load party details');
    } finally {
      setLoading(false);
    }
  };

  const handleLeave = async () => {
    try {
      await apiClient.post(`/party/${partyId}/leave`);
      navigate('/parties');
    } catch (err) {
      setError('Failed to leave party');
    }
  };

  const handleStart = async () => {
    try {
      await apiClient.post(`/party/${partyId}/start`);
      navigate(`/game/${partyId}`);
    } catch (err) {
      setError('Failed to start game');
    }
  };

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="flex items-center text-white">
          <Loader className="w-8 h-8 mr-3 animate-spin text-amber-400" />
          <span className="text-xl">Loading party...</span>
        </div>
      </div>
    );
  }

  if (!party) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700 text-center">
          <Users className="w-16 h-16 text-gray-500 mx-auto mb-4" />
          <h2 className="text-2xl font-bold text-white mb-4">Party Not Found</h2>
          <p className="text-gray-400 mb-6">The party you're looking for doesn't exist.</p>
          <button
            onClick={() => navigate('/parties')}
            className="inline-flex items-center px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors"
          >
            <ArrowLeft className="w-4 h-4 mr-2" />
            Back to Parties
          </button>
        </div>
      </div>
    );
  }

  const isOwner = user?.id === party.ownerId;
  const playerCount = party.players?.length || 0;
  const minPlayers = 3; // Game rule from README line 89
  const maxPlayers = party.settings?.playerCount || 5;

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            {/* Logo */}
            <div className="flex items-center">
              <Dice6 className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">ZapZap</h1>
            </div>

            {/* User info and logout */}
            <div className="flex items-center space-x-4">
              <span className="text-gray-300">
                Welcome, <span className="font-semibold text-white">{user?.username}</span>
              </span>
              <button
                onClick={handleLogout}
                className="flex items-center px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition-colors"
              >
                <LogOut className="w-4 h-4 mr-2" />
                Logout
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        {/* Back to parties link */}
        <button
          onClick={() => navigate('/parties')}
          className="inline-flex items-center text-gray-300 hover:text-white mb-6 transition-colors"
        >
          <ArrowLeft className="w-4 h-4 mr-2" />
          Back to Parties
        </button>

        {/* Party card */}
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700 mb-6">
          {/* Party header */}
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-3xl font-bold text-white">{party.name}</h2>
            {isOwner && (
              <span className="inline-flex items-center px-3 py-1 bg-amber-400/20 text-amber-400 border border-amber-400/30 rounded-full text-sm font-semibold">
                <Crown className="w-4 h-4 mr-1" />
                Owner
              </span>
            )}
          </div>

          {/* Party settings */}
          <div className="bg-slate-700 rounded-lg p-4 mb-6">
            <div className="flex items-center mb-3">
              <Settings className="w-5 h-5 text-amber-400 mr-2" />
              <h3 className="text-lg font-semibold text-white">Game Settings</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Max Players:</span>
                <span className="text-white font-medium">{maxPlayers} players</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Hand Size:</span>
                <span className="text-white font-medium">{party.settings?.handSize || 7} cards</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Status:</span>
                <span className={`font-medium ${
                  party.status === 'playing' ? 'text-amber-400' : 'text-green-400'
                }`}>
                  {party.status === 'playing' ? 'Playing' : 'Waiting'}
                </span>
              </div>
            </div>
          </div>

          {/* Players section */}
          <div className="mb-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-xl font-semibold text-white flex items-center">
                <Users className="w-5 h-5 mr-2 text-amber-400" />
                Players ({playerCount}/{maxPlayers})
              </h3>
              {playerCount < minPlayers && (
                <span className="text-amber-400 text-sm">
                  Need {minPlayers - playerCount} more player{minPlayers - playerCount > 1 ? 's' : ''} to start
                </span>
              )}
            </div>

            {/* Players grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {party.players?.map((player) => (
                <div
                  key={player.userId}
                  className="bg-slate-700 rounded-lg p-4 border border-slate-600 hover:border-amber-400/50 transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-white font-medium">{player.username || 'Unknown'}</span>
                      {player.userType === 'bot' && (
                        <span className="flex items-center text-xs bg-purple-500/20 text-purple-400 border border-purple-500/30 px-2 py-0.5 rounded-full">
                          <Bot className="w-3 h-3 mr-1" />
                          {player.botDifficulty?.charAt(0).toUpperCase() + player.botDifficulty?.slice(1)}
                        </span>
                      )}
                    </div>
                    {player.userId === party.ownerId && (
                      <Crown className="w-4 h-4 text-amber-400" />
                    )}
                  </div>
                </div>
              ))}

              {/* Empty player slots */}
              {Array.from({ length: maxPlayers - playerCount }).map((_, index) => (
                <div
                  key={`empty-${index}`}
                  className="bg-slate-700/30 rounded-lg p-4 border border-slate-600 border-dashed"
                >
                  <span className="text-gray-500 font-medium">Waiting for player...</span>
                </div>
              ))}
            </div>
          </div>

          {/* Error message */}
          {error && (
            <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg mb-6" role="alert">
              {error}
            </div>
          )}

          {/* Action buttons */}
          <div className="flex flex-col sm:flex-row gap-4">
            {isOwner && (
              <button
                onClick={handleStart}
                disabled={playerCount < minPlayers}
                className="flex-1 flex items-center justify-center px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-60 disabled:cursor-not-allowed"
                title={playerCount < minPlayers ? `Need at least ${minPlayers} players to start` : ''}
              >
                <Play className="w-5 h-5 mr-2" />
                Start Game
                {playerCount < minPlayers && ` (${playerCount}/${minPlayers})`}
              </button>
            )}

            <button
              onClick={handleLeave}
              className="flex-1 flex items-center justify-center px-6 py-3 bg-slate-700 hover:bg-slate-600 text-white font-semibold rounded-lg transition-colors"
            >
              <ArrowLeft className="w-5 h-5 mr-2" />
              Leave Party
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default PartyLobby;
