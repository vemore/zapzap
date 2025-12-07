import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Dice6, LogOut, Plus, Loader, Users, History, BarChart3, Shield } from 'lucide-react';
import { apiClient } from '../../services/api';
import { useAuth } from '../../contexts/AuthContext';

function PartyList() {
  const [parties, setParties] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const navigate = useNavigate();
  const { user, logout } = useAuth();

  useEffect(() => {
    fetchParties();
  }, []);

  const fetchParties = async () => {
    try {
      const response = await apiClient.get('/party');
      setParties(response.data.parties || []);
      setError('');
    } catch (err) {
      setError('Failed to fetch parties');
    } finally {
      setLoading(false);
    }
  };

  const handleJoin = async (partyId) => {
    try {
      await apiClient.post(`/party/${partyId}/join`);
      navigate(`/party/${partyId}`);
    } catch (err) {
      // If already in party, just navigate to it
      if (err.response?.data?.code === 'ALREADY_IN_PARTY') {
        navigate(`/party/${partyId}`);
      } else {
        setError('Failed to join party');
      }
    }
  };

  const handleContinue = (partyId, isPlaying) => {
    if (isPlaying) {
      navigate(`/game/${partyId}`);
    } else {
      navigate(`/party/${partyId}`);
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
          <span className="text-xl">Loading parties...</span>
        </div>
      </div>
    );
  }

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

            {/* Navigation and User info */}
            <div className="flex items-center space-x-4">
              {/* Navigation Links */}
              <Link
                to="/history"
                className="flex items-center px-3 py-2 text-gray-300 hover:text-white hover:bg-slate-600 rounded-lg transition-colors"
              >
                <History className="w-4 h-4 mr-1" />
                History
              </Link>
              <Link
                to="/stats"
                className="flex items-center px-3 py-2 text-gray-300 hover:text-white hover:bg-slate-600 rounded-lg transition-colors"
              >
                <BarChart3 className="w-4 h-4 mr-1" />
                Stats
              </Link>
              {user?.isAdmin && (
                <Link
                  to="/admin"
                  className="flex items-center px-3 py-2 text-amber-300 hover:text-amber-200 hover:bg-amber-900/30 rounded-lg transition-colors"
                >
                  <Shield className="w-4 h-4 mr-1" />
                  Admin
                </Link>
              )}
              <span className="text-gray-500">|</span>
              <span className="text-gray-300">
                <span className="font-semibold text-white">{user?.username}</span>
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
        {/* Page header with Create button */}
        <div className="flex items-center justify-between mb-8">
          <h2 className="text-3xl font-bold text-white">Available Parties</h2>
          <Link to="/create-party">
            <button className="flex items-center px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors shadow-lg">
              <Plus className="w-5 h-5 mr-2" />
              Create Party
            </button>
          </Link>
        </div>

        {/* Error message */}
        {error && (
          <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg mb-6" role="alert">
            {error}
          </div>
        )}

        {/* Empty state */}
        {parties.length === 0 ? (
          <div className="bg-slate-800 rounded-lg shadow-xl p-12 border border-slate-700 text-center">
            <Users className="w-16 h-16 text-gray-500 mx-auto mb-4" />
            <h3 className="text-xl font-semibold text-white mb-2">No Parties Available</h3>
            <p className="text-gray-400 mb-6">Be the first to create a party and start playing!</p>
            <Link to="/create-party">
              <button className="inline-flex items-center px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors">
                <Plus className="w-5 h-5 mr-2" />
                Create Your First Party
              </button>
            </Link>
          </div>
        ) : (
          /* Parties grid */
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {parties.map((party) => {
              const maxPlayers = party.maxPlayers || party.settings?.playerCount || 5;
              const playerCount = party.playerCount || 0;
              const isFull = playerCount >= maxPlayers;
              const isPlaying = party.status === 'playing';
              const isMember = party.isMember || false;

              return (
                <div
                  key={party.id}
                  className={`bg-slate-800 rounded-lg shadow-xl p-6 border transition-all hover:shadow-2xl ${
                    isMember ? 'border-green-500 hover:border-green-400' : 'border-slate-700 hover:border-amber-400'
                  }`}
                >
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-xl font-bold text-white">{party.name}</h3>
                    {isMember && (
                      <span className="text-xs bg-green-500/20 text-green-400 border border-green-500/30 px-2 py-1 rounded-full">
                        Joined
                      </span>
                    )}
                  </div>

                  <div className="space-y-2 mb-4">
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-gray-400">Players:</span>
                      <span className="text-white font-medium">
                        {playerCount} / {maxPlayers}
                      </span>
                    </div>
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-gray-400">Status:</span>
                      <span className={`font-medium ${
                        isPlaying ? 'text-amber-400' : 'text-green-400'
                      }`}>
                        {isPlaying ? 'Playing' : 'Waiting'}
                      </span>
                    </div>
                  </div>

                  {isMember ? (
                    <button
                      onClick={() => handleContinue(party.id, isPlaying)}
                      className="w-full py-2 rounded-lg font-semibold transition-colors bg-green-600 hover:bg-green-700 text-white"
                    >
                      {isPlaying ? 'Continue Game' : 'Return to Lobby'}
                    </button>
                  ) : (
                    <button
                      onClick={() => handleJoin(party.id)}
                      disabled={isFull || isPlaying}
                      className="w-full py-2 rounded-lg font-semibold transition-colors disabled:cursor-not-allowed disabled:bg-gray-600 disabled:text-gray-400 bg-amber-500 hover:bg-amber-600 text-white"
                    >
                      {isPlaying ? 'In Progress' : isFull ? 'Full' : 'Join Party'}
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

export default PartyList;
