import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { BarChart3, Trophy, Target, Zap, Medal, Loader, TrendingUp, Hash, Bot } from 'lucide-react';
import { apiClient } from '../../services/api';
import { useAuth } from '../../contexts/AuthContext';

function Statistics() {
  const { user } = useAuth();
  const [personalStats, setPersonalStats] = useState(null);
  const [leaderboard, setLeaderboard] = useState([]);
  const [botStats, setBotStats] = useState(null);
  const [loadingStats, setLoadingStats] = useState(true);
  const [loadingLeaderboard, setLoadingLeaderboard] = useState(true);
  const [loadingBotStats, setLoadingBotStats] = useState(true);
  const [selectedDifficulty, setSelectedDifficulty] = useState(null);

  useEffect(() => {
    fetchPersonalStats();
    fetchLeaderboard();
    fetchBotStats();
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

  const fetchBotStats = async () => {
    setLoadingBotStats(true);
    try {
      const response = await apiClient.get('/stats/bots');
      setBotStats(response.data);
    } catch (err) {
      console.error('Failed to fetch bot stats:', err);
    } finally {
      setLoadingBotStats(false);
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
                {leaderboard.map((entry) => (
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

        {/* Bot Statistics - Full width */}
        <div className="mt-6 bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h2 className="text-xl font-bold text-white mb-6 flex items-center">
            <Bot className="w-6 h-6 text-purple-400 mr-2" />
            Bot Statistics
          </h2>
          <BotStatistics
            botStats={botStats}
            loading={loadingBotStats}
            selectedDifficulty={selectedDifficulty}
            setSelectedDifficulty={setSelectedDifficulty}
            formatPercentage={formatPercentage}
          />
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

function BotStatistics({ botStats, loading, selectedDifficulty, setSelectedDifficulty, formatPercentage }) {
  const difficultyColors = {
    easy: { bg: 'bg-green-900/30', border: 'border-green-500/50', text: 'text-green-400', tabBg: 'bg-green-900/50' },
    medium: { bg: 'bg-yellow-900/30', border: 'border-yellow-500/50', text: 'text-yellow-400', tabBg: 'bg-yellow-900/50' },
    hard: { bg: 'bg-red-900/30', border: 'border-red-500/50', text: 'text-red-400', tabBg: 'bg-red-900/50' },
    hard_vince: { bg: 'bg-purple-900/30', border: 'border-purple-500/50', text: 'text-purple-400', tabBg: 'bg-purple-900/50' },
    ml: { bg: 'bg-cyan-900/30', border: 'border-cyan-500/50', text: 'text-cyan-400', tabBg: 'bg-cyan-900/50' },
    drl: { bg: 'bg-indigo-900/30', border: 'border-indigo-500/50', text: 'text-indigo-400', tabBg: 'bg-indigo-900/50' },
    llm: { bg: 'bg-pink-900/30', border: 'border-pink-500/50', text: 'text-pink-400', tabBg: 'bg-pink-900/50' }
  };

  const difficultyLabels = {
    easy: 'Easy',
    medium: 'Medium',
    hard: 'Hard',
    hard_vince: 'Hard Vince',
    ml: 'ML (TensorFlow)',
    drl: 'DRL (Deep RL)',
    llm: 'LLM (Llama 3.3)'
  };

  const difficultyStrategies = {
    easy: {
      title: 'Random Strategy',
      description: 'Plays random valid combinations, prefers multi-card plays. Calls ZapZap immediately when eligible (hand ≤ 5). Always draws from deck. Random hand size selection.'
    },
    medium: {
      title: 'High-Value Priority',
      description: 'Prioritizes playing high-value cards (K, Q, J, 10). More conservative ZapZap (hand ≤ 3). Draws from discard if it helps complete combinations. Prefers moderate hand sizes (5-6).'
    },
    hard: {
      title: 'Optimal Minimization',
      description: 'Evaluates all plays to minimize remaining hand value. Strategic ZapZap timing based on round progression. Analyzes discard pile for best card acquisitions. Prefers smaller hands (4-5) for faster ZapZap.'
    },
    hard_vince: {
      title: 'Advanced Vince Strategy',
      description: 'Builds on Hard strategy with Joker management: keeps Jokers for sequences when opponents have >3 cards, plays them when opponent is close to ZapZap. Tracks opponent card picks and played cards for probability-based decisions. Prioritizes picking up discarded Jokers strategically.'
    },
    ml: {
      title: 'TensorFlow ML Strategy',
      description: 'Uses a trained TensorFlow model to evaluate game states and select optimal plays. Learns patterns from game simulations to improve decision-making over time.'
    },
    drl: {
      title: 'Deep Reinforcement Learning',
      description: 'Employs deep Q-learning with experience replay. Learns optimal policies through self-play and exploration. Adapts strategy based on opponent behavior patterns.'
    },
    llm: {
      title: 'Large Language Model (Llama 3.3)',
      description: 'Powered by Llama 3.3 via AWS Bedrock. Uses natural language understanding of game rules and context to make strategic decisions. Analyzes hand, game state, and play history.'
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Loader className="w-6 h-6 text-purple-400 animate-spin mr-2" />
        <span className="text-gray-400">Loading bot statistics...</span>
      </div>
    );
  }

  if (!botStats || botStats.byDifficulty.length === 0) {
    return (
      <p className="text-gray-400 text-center py-8">
        No bot statistics available yet. Play some games with bots!
      </p>
    );
  }

  return (
    <div className="space-y-6">
      {/* Totals Summary */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard
          icon={<Bot className="w-5 h-5" />}
          label="Total Bots"
          value={botStats.totals.totalBots}
          color="purple"
        />
        <StatCard
          icon={<Hash className="w-5 h-5" />}
          label="Games Played"
          value={botStats.totals.totalGamesPlayed}
          color="blue"
        />
        <StatCard
          icon={<Trophy className="w-5 h-5" />}
          label="Overall Win Rate"
          value={formatPercentage(botStats.totals.overallWinRate)}
          color="amber"
        />
        <StatCard
          icon={<Zap className="w-5 h-5" />}
          label="ZapZap Success"
          value={formatPercentage(botStats.totals.overallZapzapSuccessRate)}
          color="green"
        />
      </div>

      {/* Difficulty Filter Tabs */}
      <div className="flex flex-wrap gap-2 border-b border-slate-700 pb-3">
        <button
          onClick={() => setSelectedDifficulty(null)}
          className={`px-4 py-2 rounded-lg transition-colors ${
            selectedDifficulty === null
              ? 'bg-slate-600 text-white'
              : 'text-gray-400 hover:text-white hover:bg-slate-700'
          }`}
        >
          All Difficulties
        </button>
        {['easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm'].map(diff => (
          <button
            key={diff}
            onClick={() => setSelectedDifficulty(diff)}
            className={`px-4 py-2 rounded-lg transition-colors ${
              selectedDifficulty === diff
                ? `${difficultyColors[diff].tabBg} ${difficultyColors[diff].text}`
                : 'text-gray-400 hover:text-white hover:bg-slate-700'
            }`}
          >
            {difficultyLabels[diff]}
          </button>
        ))}
      </div>

      {/* Stats by Difficulty */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {botStats.byDifficulty
          .filter(d => !selectedDifficulty || d.difficulty === selectedDifficulty)
          .map(diffStats => (
            <div
              key={diffStats.difficulty}
              className={`rounded-lg p-4 border ${difficultyColors[diffStats.difficulty].bg} ${difficultyColors[diffStats.difficulty].border}`}
            >
              <div className="flex items-center justify-between mb-2">
                <h4 className={`font-bold text-lg ${difficultyColors[diffStats.difficulty].text}`}>
                  {difficultyLabels[diffStats.difficulty]}
                </h4>
                <span className="text-gray-400 text-sm">
                  {diffStats.botCount} bot{diffStats.botCount !== 1 ? 's' : ''}
                </span>
              </div>

              {/* Strategy Description */}
              <div className="mb-4">
                <p className={`text-xs font-medium ${difficultyColors[diffStats.difficulty].text}`}>
                  {difficultyStrategies[diffStats.difficulty].title}
                </p>
                <p className="text-gray-400 text-xs mt-1">
                  {difficultyStrategies[diffStats.difficulty].description}
                </p>
              </div>

              <div className="grid grid-cols-2 gap-3 text-center mb-4">
                <div>
                  <p className="text-gray-400 text-xs">Games</p>
                  <p className="text-xl font-bold text-white">{diffStats.gamesPlayed}</p>
                </div>
                <div>
                  <p className="text-gray-400 text-xs">Rounds</p>
                  <p className="text-xl font-bold text-white">{diffStats.roundsPlayed}</p>
                </div>
                <div>
                  <p className="text-gray-400 text-xs">Win Rate</p>
                  <p className="text-xl font-bold text-green-400">{formatPercentage(diffStats.winRate)}</p>
                </div>
                <div>
                  <p className="text-gray-400 text-xs">Round Wins</p>
                  <p className="text-xl font-bold text-amber-400">{formatPercentage(diffStats.roundWinRate)}</p>
                </div>
              </div>

              {/* ZapZap Stats */}
              <div className="pt-3 border-t border-slate-600">
                <p className="text-gray-500 text-xs mb-2 text-center">ZapZap Performance</p>
                <div className="grid grid-cols-2 gap-2 text-center">
                  <div>
                    <p className="text-gray-500 text-xs">Calls</p>
                    <p className="font-bold text-white">{diffStats.zapzaps.total}</p>
                  </div>
                  <div>
                    <p className="text-gray-500 text-xs">Success Rate</p>
                    <p className="font-bold text-purple-400">{formatPercentage(diffStats.zapzaps.successRate)}</p>
                  </div>
                </div>
              </div>
            </div>
          ))}
      </div>

      {/* Individual Bot Breakdown */}
      {selectedDifficulty && (
        <div className="mt-4">
          <h4 className="text-white font-semibold mb-3">Individual Bot Performance</h4>
          <div className="space-y-2">
            {botStats.byBot
              .filter(b => b.difficulty === selectedDifficulty)
              .map(bot => (
                <div
                  key={bot.botId}
                  className="flex items-center justify-between p-3 bg-slate-700/50 rounded-lg"
                >
                  <div>
                    <p className="text-white font-medium">{bot.username}</p>
                    <p className="text-gray-400 text-xs">
                      {bot.gamesPlayed} games | {bot.wins} wins | {bot.roundsPlayed} rounds
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="font-bold text-green-400">{formatPercentage(bot.winRate)}</p>
                    <p className="text-gray-500 text-xs">win rate</p>
                  </div>
                </div>
              ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default Statistics;
