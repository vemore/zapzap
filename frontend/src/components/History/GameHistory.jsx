import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { History, Globe, User, Trophy, Calendar, Users, Loader, ChevronRight } from 'lucide-react';
import { apiClient } from '../../services/api';
import { useAuth } from '../../contexts/AuthContext';

function GameHistory() {
  const { user } = useAuth();
  const [activeTab, setActiveTab] = useState('personal');
  const [games, setGames] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchGames();
  }, [activeTab]);

  const fetchGames = async () => {
    setLoading(true);
    setError('');
    try {
      const endpoint = activeTab === 'personal' ? '/history' : '/history/public';
      const response = await apiClient.get(endpoint);
      setGames(response.data.games || []);
    } catch (err) {
      console.error('Failed to fetch games:', err);
      setError('Failed to load game history');
    } finally {
      setLoading(false);
    }
  };

  const formatDate = (timestamp) => {
    // Backend stores timestamps in seconds, JavaScript expects milliseconds
    const timestampMs = timestamp < 10000000000 ? timestamp * 1000 : timestamp;
    return new Date(timestampMs).toLocaleDateString('fr-FR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div className="flex items-center">
              <History className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">Game History</h1>
            </div>
            <Link
              to="/parties"
              className="text-gray-300 hover:text-white transition-colors"
            >
              Back to Parties
            </Link>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
        {/* Tabs */}
        <div className="flex space-x-4 mb-6">
          <button
            onClick={() => setActiveTab('personal')}
            className={`flex items-center px-4 py-2 rounded-lg font-medium transition-colors ${
              activeTab === 'personal'
                ? 'bg-amber-500 text-white'
                : 'bg-slate-700 text-gray-300 hover:bg-slate-600'
            }`}
          >
            <User className="w-4 h-4 mr-2" />
            My Games
          </button>
          <button
            onClick={() => setActiveTab('public')}
            className={`flex items-center px-4 py-2 rounded-lg font-medium transition-colors ${
              activeTab === 'public'
                ? 'bg-amber-500 text-white'
                : 'bg-slate-700 text-gray-300 hover:bg-slate-600'
            }`}
          >
            <Globe className="w-4 h-4 mr-2" />
            Public Games
          </button>
        </div>

        {/* Loading */}
        {loading && (
          <div className="flex items-center justify-center py-12">
            <Loader className="w-8 h-8 text-amber-400 animate-spin mr-3" />
            <span className="text-gray-300">Loading games...</span>
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="bg-red-900/30 border border-red-700 rounded-lg p-4 text-red-300">
            {error}
          </div>
        )}

        {/* Games List */}
        {!loading && !error && (
          <div className="space-y-4">
            {games.length === 0 ? (
              <div className="bg-slate-800 rounded-lg p-8 text-center border border-slate-700">
                <History className="w-12 h-12 text-gray-500 mx-auto mb-4" />
                <p className="text-gray-400">
                  {activeTab === 'personal'
                    ? 'No finished games yet. Play some games to see your history!'
                    : 'No public games have been completed yet.'}
                </p>
              </div>
            ) : (
              games.map((game) => (
                <Link
                  key={game.partyId}
                  to={`/history/${game.partyId}`}
                  className="block bg-slate-800 rounded-lg p-5 border border-slate-700 hover:border-amber-500/50 transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex-grow">
                      <div className="flex items-center mb-2">
                        <h3 className="text-lg font-semibold text-white mr-3">
                          {game.partyName}
                        </h3>
                        {game.wasGoldenScore && (
                          <span className="text-xs bg-yellow-500/20 text-yellow-400 border border-yellow-500/30 px-2 py-1 rounded-full">
                            Golden Score
                          </span>
                        )}
                      </div>
                      <div className="flex items-center text-gray-400 text-sm space-x-4">
                        <span className="flex items-center">
                          <Trophy className="w-4 h-4 mr-1 text-amber-400" />
                          {game.winnerUsername} ({game.winnerFinalScore} pts)
                        </span>
                        <span className="flex items-center">
                          <Users className="w-4 h-4 mr-1" />
                          {game.playerCount} players
                        </span>
                        <span className="flex items-center">
                          <Calendar className="w-4 h-4 mr-1" />
                          {formatDate(game.finishedAt)}
                        </span>
                        <span>
                          {game.totalRounds} round{game.totalRounds > 1 ? 's' : ''}
                        </span>
                      </div>
                    </div>
                    <ChevronRight className="w-5 h-5 text-gray-500" />
                  </div>
                </Link>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export default GameHistory;
