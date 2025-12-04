import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { Trophy, Crown, Zap, ArrowLeft, Loader, Users, Calendar, Target } from 'lucide-react';
import { apiClient } from '../../services/api';
import PlayingCard from '../Game/PlayingCard';

function GameDetails() {
  const { partyId } = useParams();
  const [gameData, setGameData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchGameDetails();
  }, [partyId]);

  const fetchGameDetails = async () => {
    setLoading(true);
    setError('');
    try {
      const response = await apiClient.get(`/history/${partyId}`);
      setGameData(response.data);
    } catch (err) {
      console.error('Failed to fetch game details:', err);
      setError(err.response?.data?.error || 'Failed to load game details');
    } finally {
      setLoading(false);
    }
  };

  const formatDate = (timestamp) => {
    return new Date(timestamp).toLocaleDateString('fr-FR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="flex items-center text-white">
          <Loader className="w-8 h-8 mr-3 animate-spin text-amber-400" />
          <span className="text-xl">Loading game details...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="bg-slate-800 rounded-lg p-8 text-center border border-slate-700 max-w-md">
          <p className="text-red-400 mb-4">{error}</p>
          <Link
            to="/history"
            className="text-amber-400 hover:text-amber-300 transition-colors"
          >
            Back to History
          </Link>
        </div>
      </div>
    );
  }

  const { game, players, rounds } = gameData;

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div className="flex items-center">
              <Link
                to="/history"
                className="text-gray-400 hover:text-white mr-4 transition-colors"
              >
                <ArrowLeft className="w-6 h-6" />
              </Link>
              <Trophy className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">{game.partyName}</h1>
            </div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 py-6 sm:px-6 lg:px-8 space-y-6">
        {/* Game Summary */}
        <div className="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-bold text-white">Game Summary</h2>
            {game.wasGoldenScore && (
              <span className="text-sm bg-yellow-500/20 text-yellow-400 border border-yellow-500/30 px-3 py-1 rounded-full">
                Golden Score Finish
              </span>
            )}
          </div>

          {/* Winner Banner */}
          <div className="bg-gradient-to-r from-amber-900/50 via-yellow-800/50 to-amber-900/50 rounded-lg p-6 border-2 border-amber-400 mb-6">
            <div className="flex items-center justify-center mb-2">
              <Crown className="w-8 h-8 text-yellow-400 mr-2" />
              <span className="text-2xl font-bold text-yellow-400">WINNER</span>
              <Crown className="w-8 h-8 text-yellow-400 ml-2" />
            </div>
            <p className="text-3xl font-bold text-white text-center">{game.winner.username}</p>
            <p className="text-amber-300 text-center mt-2">Final Score: {game.winner.finalScore} points</p>
          </div>

          {/* Game Info */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-center">
            <div className="bg-slate-700/50 rounded-lg p-4">
              <Users className="w-6 h-6 text-amber-400 mx-auto mb-2" />
              <p className="text-gray-400 text-sm">Players</p>
              <p className="text-white font-bold text-lg">{game.playerCount}</p>
            </div>
            <div className="bg-slate-700/50 rounded-lg p-4">
              <Target className="w-6 h-6 text-amber-400 mx-auto mb-2" />
              <p className="text-gray-400 text-sm">Rounds</p>
              <p className="text-white font-bold text-lg">{game.totalRounds}</p>
            </div>
            <div className="bg-slate-700/50 rounded-lg p-4">
              <Calendar className="w-6 h-6 text-amber-400 mx-auto mb-2" />
              <p className="text-gray-400 text-sm">Finished</p>
              <p className="text-white font-bold text-sm">{formatDate(game.finishedAt)}</p>
            </div>
            <div className="bg-slate-700/50 rounded-lg p-4">
              <Trophy className="w-6 h-6 text-amber-400 mx-auto mb-2" />
              <p className="text-gray-400 text-sm">Visibility</p>
              <p className="text-white font-bold text-lg capitalize">{game.visibility}</p>
            </div>
          </div>
        </div>

        {/* Final Standings */}
        <div className="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h2 className="text-xl font-bold text-white mb-4">Final Standings</h2>
          <div className="space-y-3">
            {players.map((player) => (
              <div
                key={player.userId}
                className={`flex items-center justify-between p-4 rounded-lg border ${
                  player.isWinner
                    ? 'bg-amber-900/20 border-amber-400'
                    : 'bg-slate-700/50 border-slate-600'
                }`}
              >
                <div className="flex items-center">
                  <span className={`w-8 h-8 flex items-center justify-center rounded-full font-bold mr-3 ${
                    player.finishPosition === 1
                      ? 'bg-amber-400 text-slate-900'
                      : player.finishPosition === 2
                      ? 'bg-gray-300 text-slate-900'
                      : player.finishPosition === 3
                      ? 'bg-orange-400 text-slate-900'
                      : 'bg-slate-600 text-white'
                  }`}>
                    {player.finishPosition}
                  </span>
                  <div>
                    <p className="text-white font-semibold">{player.username}</p>
                    <div className="flex items-center text-gray-400 text-sm space-x-3">
                      <span className="flex items-center">
                        <Zap className="w-3 h-3 mr-1 text-purple-400" />
                        {player.successfulZapZaps}/{player.totalZapZapCalls} ZapZaps
                      </span>
                      <span>
                        {player.lowestHandCount} lowest hands
                      </span>
                    </div>
                  </div>
                </div>
                <div className="text-right">
                  <p className={`font-bold text-lg ${player.isWinner ? 'text-amber-400' : 'text-white'}`}>
                    {player.finalScore} pts
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Round-by-Round Scores */}
        <div className="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h2 className="text-xl font-bold text-white mb-4">Round-by-Round Scores</h2>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-slate-600">
                  <th className="text-left text-gray-400 py-3 px-4">Round</th>
                  {players.map((player) => (
                    <th key={player.userId} className="text-center text-gray-400 py-3 px-4">
                      {player.username}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rounds.map((round) => (
                  <tr key={round.roundNumber} className="border-b border-slate-700">
                    <td className="py-3 px-4 text-white font-medium">
                      Round {round.roundNumber}
                    </td>
                    {players.map((player) => {
                      const roundPlayer = round.players.find(
                        (p) => p.userId === player.userId
                      );
                      if (!roundPlayer) return <td key={player.userId} className="text-center py-3 px-4">-</td>;

                      return (
                        <td key={player.userId} className="text-center py-3 px-4">
                          <div className="flex flex-col items-center">
                            <span className={`font-bold ${
                              roundPlayer.isLowestHand
                                ? 'text-green-400'
                                : roundPlayer.wasCounterActed
                                ? 'text-red-400'
                                : 'text-white'
                            }`}>
                              +{roundPlayer.scoreThisRound}
                            </span>
                            <span className="text-gray-500 text-xs">
                              ({roundPlayer.totalScoreAfter})
                            </span>
                            <div className="flex items-center gap-1 mt-1">
                              {roundPlayer.isZapZapCaller && (
                                <Zap className={`w-3 h-3 ${
                                  roundPlayer.zapZapSuccess ? 'text-green-400' : 'text-red-400'
                                }`} />
                              )}
                              {roundPlayer.isLowestHand && (
                                <Crown className="w-3 h-3 text-amber-400" />
                              )}
                              {roundPlayer.isEliminated && (
                                <span className="text-xs text-red-400">X</span>
                              )}
                            </div>
                          </div>
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-4 flex items-center gap-4 text-xs text-gray-500">
            <span className="flex items-center">
              <Crown className="w-3 h-3 text-amber-400 mr-1" /> Lowest hand
            </span>
            <span className="flex items-center">
              <Zap className="w-3 h-3 text-green-400 mr-1" /> Successful ZapZap
            </span>
            <span className="flex items-center">
              <Zap className="w-3 h-3 text-red-400 mr-1" /> Failed ZapZap
            </span>
            <span className="text-red-400">X = Eliminated</span>
          </div>
        </div>
      </div>
    </div>
  );
}

export default GameDetails;
