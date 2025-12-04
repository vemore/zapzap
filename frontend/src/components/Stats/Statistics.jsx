import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { BarChart3, Trophy, Target, Zap, Users, Medal, Loader, TrendingUp, Hash } from 'lucide-react';
import { apiClient } from '../../services/api';
import { useAuth } from '../../contexts/AuthContext';

function Statistics() {
  const { user } = useAuth();
  const [personalStats, setPersonalStats] = useState(null);
  const [leaderboard, setLeaderboard] = useState([]);
  const [loadingStats, setLoadingStats] = useState(true);
  const [loadingLeaderboard, setLoadingLeaderboard] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchPersonalStats();
    fetchLeaderboard();
  }, []);

  const fetchPersonalStats = async () => {
    setLoadingStats(true);
    try {
      const response = await apiClient.get('/stats/me');
      setPersonalStats(response.data);
    } catch (err) {
      console.error('Failed to fetch stats:', err);
    } finally {
      setLoadingStats(false);
    }
  };

  const fetchLeaderboard = async () => {
    setLoadingLeaderboard(true);
    try {
      const response = await apiClient.get('/stats/leaderboard?minGames=1&limit=20');
      setLeaderboard(response.data.leaderboard || []);
    } catch (err) {
      console.error('Failed to fetch leaderboard:', err);
    } finally {
      setLoadingLeaderboard(false);
    }
  };

  const formatPercentage = (value) => {
    return (value * 100).toFixed(1) + '%';
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div className="flex items-center">
              <BarChart3 className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">Statistics</h1>
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
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Personal Stats */}
          <div className="bg-slate-800 rounded-lg p-6 border border-slate-700">
            <h2 className="text-xl font-bold text-white mb-6 flex items-center">
              <Target className="w-6 h-6 text-amber-400 mr-2" />
              Personal Statistics
            </h2>

            {loadingStats ? (
              <div className="flex items-center justify-center py-8">
                <Loader className="w-6 h-6 text-amber-400 animate-spin mr-2" />
                <span className="text-gray-400">Loading stats...</span>
              </div>
            ) : personalStats ? (
              <div className="space-y-6">
                {/* Main Stats */}
                <div className="grid grid-cols-2 gap-4">
                  <StatCard
                    icon={<Hash className="w-5 h-5" />}
                    label="Games Played"
                    value={personalStats.stats.gamesPlayed}
                    color="blue"
                  />
                  <StatCard
                    icon={<Trophy className="w-5 h-5" />}
                    label="Wins"
                    value={personalStats.stats.wins}
                    color="amber"
                  />
                  <StatCard
                    icon={<TrendingUp className="w-5 h-5" />}
                    label="Win Rate"
                    value={formatPercentage(personalStats.stats.winRate)}
                    color="green"
                  />
                  <StatCard
                    icon={<Target className="w-5 h-5" />}
                    label="Avg Score"
                    value={personalStats.stats.averageScore?.toFixed(1) || '0'}
                    color="purple"
                  />
                </div>

                {/* ZapZap Stats */}
                <div className="bg-slate-700/50 rounded-lg p-4">
                  <h3 className="text-white font-semibold mb-3 flex items-center">
                    <Zap className="w-5 h-5 text-purple-400 mr-2" />
                    ZapZap Performance
                  </h3>
                  <div className="grid grid-cols-3 gap-3 text-center">
                    <div>
                      <p className="text-gray-400 text-sm">Total</p>
                      <p className="text-2xl font-bold text-white">{personalStats.stats.zapzaps.total}</p>
                    </div>
                    <div>
                      <p className="text-gray-400 text-sm">Successful</p>
                      <p className="text-2xl font-bold text-green-400">{personalStats.stats.zapzaps.successful}</p>
                    </div>
                    <div>
                      <p className="text-gray-400 text-sm">Failed</p>
                      <p className="text-2xl font-bold text-red-400">{personalStats.stats.zapzaps.failed}</p>
                    </div>
                  </div>
                  {personalStats.stats.zapzaps.total > 0 && (
                    <div className="mt-3 pt-3 border-t border-slate-600 text-center">
                      <p className="text-gray-400 text-sm">
                        Success Rate: <span className="text-white font-bold">{formatPercentage(personalStats.stats.zapzaps.successRate)}</span>
                      </p>
                    </div>
                  )}
                </div>

                {/* Additional Stats */}
                <div className="grid grid-cols-2 gap-4">
                  <div className="bg-slate-700/50 rounded-lg p-4 text-center">
                    <p className="text-gray-400 text-sm">Best Score</p>
                    <p className="text-2xl font-bold text-amber-400">{personalStats.stats.bestScore || '-'}</p>
                  </div>
                  <div className="bg-slate-700/50 rounded-lg p-4 text-center">
                    <p className="text-gray-400 text-sm">Total Rounds</p>
                    <p className="text-2xl font-bold text-white">{personalStats.stats.totalRoundsPlayed}</p>
                  </div>
                </div>
              </div>
            ) : (
              <p className="text-gray-400 text-center py-8">
                No statistics available yet. Play some games!
              </p>
            )}
          </div>

          {/* Leaderboard */}
          <div className="bg-slate-800 rounded-lg p-6 border border-slate-700">
            <h2 className="text-xl font-bold text-white mb-6 flex items-center">
              <Medal className="w-6 h-6 text-amber-400 mr-2" />
              Global Leaderboard
            </h2>

            {loadingLeaderboard ? (
              <div className="flex items-center justify-center py-8">
                <Loader className="w-6 h-6 text-amber-400 animate-spin mr-2" />
                <span className="text-gray-400">Loading leaderboard...</span>
              </div>
            ) : leaderboard.length > 0 ? (
              <div className="space-y-2">
                {leaderboard.map((entry, index) => (
                  <div
                    key={entry.userId}
                    className={`flex items-center justify-between p-3 rounded-lg ${
                      entry.userId === user?.id
                        ? 'bg-amber-900/30 border border-amber-500/50'
                        : 'bg-slate-700/50'
                    }`}
                  >
                    <div className="flex items-center">
                      <span className={`w-8 h-8 flex items-center justify-center rounded-full font-bold mr-3 ${
                        entry.rank === 1
                          ? 'bg-amber-400 text-slate-900'
                          : entry.rank === 2
                          ? 'bg-gray-300 text-slate-900'
                          : entry.rank === 3
                          ? 'bg-orange-400 text-slate-900'
                          : 'bg-slate-600 text-white'
                      }`}>
                        {entry.rank}
                      </span>
                      <div>
                        <p className={`font-semibold ${entry.userId === user?.id ? 'text-amber-300' : 'text-white'}`}>
                          {entry.username}
                          {entry.userId === user?.id && <span className="text-xs ml-2">(You)</span>}
                        </p>
                        <p className="text-gray-400 text-xs">
                          {entry.wins}/{entry.gamesPlayed} wins
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="font-bold text-green-400">{formatPercentage(entry.winRate)}</p>
                      <p className="text-gray-500 text-xs">win rate</p>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-gray-400 text-center py-8">
                No players on the leaderboard yet.
              </p>
            )}

            <p className="text-gray-500 text-xs mt-4 text-center">
              Minimum 1 game played to appear on leaderboard
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

function StatCard({ icon, label, value, color }) {
  const colorClasses = {
    blue: 'text-blue-400',
    amber: 'text-amber-400',
    green: 'text-green-400',
    purple: 'text-purple-400',
  };

  return (
    <div className="bg-slate-700/50 rounded-lg p-4">
      <div className={`${colorClasses[color]} mb-2`}>{icon}</div>
      <p className="text-gray-400 text-sm">{label}</p>
      <p className="text-2xl font-bold text-white">{value}</p>
    </div>
  );
}

export default Statistics;
