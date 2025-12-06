import { Trophy, AlertTriangle, Sparkles, Zap, ArrowRight, Loader, Crown, PartyPopper, Home } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import PlayingCard from './PlayingCard';

/**
 * RoundEnd component - displays scoring at end of round
 * @param {Object} roundData - Round results
 * @param {Function} onContinue - Continue to next round
 * @param {boolean} disabled - Disable continue button
 */
function RoundEnd({ roundData, onContinue, disabled = false }) {
  const navigate = useNavigate();

  if (!roundData) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="flex items-center text-white">
          <Loader className="w-8 h-8 mr-3 animate-spin text-amber-400" />
          <span className="text-xl">Calculating scores...</span>
        </div>
      </div>
    );
  }

  const {
    players = [],
    zapZapCaller,
    roundNumber,
    gameFinished = false,
    winner = null,
    wasCounterActed = false,
    counterActedByPlayerIndex = null
  } = roundData;

  if (players.length === 0) {
    return (
      <div className="bg-slate-800 rounded-lg shadow-xl p-12 border border-slate-700 text-center">
        <p className="text-red-400 text-lg">No players found</p>
      </div>
    );
  }

  // Find lowest hand value for this round (player who got 0 points)
  const lowestPlayer = players.find((p) => p.score === 0) || players[0];

  // Check if ZapZap was called
  const zapZapPlayer = zapZapCaller ? players.find((p) => p.id === zapZapCaller) : null;

  // Sort players by score (lowest first)
  const sortedPlayers = [...players].sort((a, b) => a.score - b.score);

  // Check for eliminated players
  const eliminatedPlayers = players.filter((p) => p.totalScore > 100);

  return (
    <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700">
      {/* Round/Game header */}
      <div className="mb-8">
        {gameFinished ? (
          // Game Finished header with winner announcement
          <div className="text-center">
            <div className="flex items-center justify-center mb-4">
              <PartyPopper className="w-10 h-10 text-amber-400 mr-3 animate-bounce" />
              <h2 className="text-4xl font-bold text-white">Game Over!</h2>
              <PartyPopper className="w-10 h-10 text-amber-400 ml-3 animate-bounce" />
            </div>
            {winner && (
              <div className="bg-gradient-to-r from-amber-900/50 via-yellow-800/50 to-amber-900/50 rounded-lg p-6 border-2 border-amber-400 mb-4">
                <div className="flex items-center justify-center mb-2">
                  <Crown className="w-8 h-8 text-yellow-400 mr-2" />
                  <span className="text-2xl font-bold text-yellow-400">WINNER</span>
                  <Crown className="w-8 h-8 text-yellow-400 ml-2" />
                </div>
                <p className="text-3xl font-bold text-white">{winner.username}</p>
                <p className="text-amber-300 mt-2">Final Score: {winner.score} points</p>
              </div>
            )}
            <p className="text-gray-400">Round {roundNumber} - Final Round</p>
          </div>
        ) : (
          // Regular round complete header
          <div className="flex items-center justify-center mb-6">
            <Trophy className="w-8 h-8 text-amber-400 mr-3" />
            <h2 className="text-3xl font-bold text-white">Round {roundNumber} Complete!</h2>
          </div>
        )}

        {/* ZapZap indicator */}
        {zapZapPlayer && (
          <div
            className={`rounded-lg p-6 border-2 ${
              wasCounterActed
                ? 'bg-red-900/30 border-red-700'
                : 'bg-green-900/30 border-green-700'
            }`}
          >
            {wasCounterActed ? (
              <>
                <div className="flex items-center justify-center mb-3">
                  <AlertTriangle className="w-6 h-6 text-red-400 mr-2" />
                  <p className="text-red-400 font-semibold text-lg">
                    <strong>{zapZapPlayer.username}</strong> called ZapZap but was{' '}
                    <strong>Counteracted!</strong>
                  </p>
                </div>
                <div className="bg-red-900/50 border border-red-800 rounded px-4 py-2 text-center">
                  <p className="text-red-200 text-sm">
                    Penalty: {zapZapPlayer.handValue} + ({players.filter(p => p.totalScore <= 100).length - 1} × 5) = {zapZapPlayer.score} points
                  </p>
                </div>
              </>
            ) : (
              <div className="flex items-center justify-center">
                <Sparkles className="w-6 h-6 text-green-400 mr-2" />
                <p className="text-green-400 font-semibold text-lg">
                  <strong>{zapZapPlayer.username}</strong> successfully called <strong>ZapZap!</strong>
                </p>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Players results */}
      <div className="space-y-4 mb-8">
        {sortedPlayers.map((player, index) => {
          const isLowest = player.id === lowestPlayer?.id;
          const isEliminated = player.totalScore > 100;
          const isZapZapCaller = player.id === zapZapCaller;

          const borderClasses = isLowest
            ? 'border-amber-400 ring-2 ring-amber-400/50'
            : isEliminated
            ? 'border-red-500 ring-2 ring-red-500/50'
            : 'border-slate-600';

          const bgClasses = isLowest
            ? 'bg-amber-900/20'
            : isEliminated
            ? 'bg-red-900/20'
            : 'bg-slate-700';

          return (
            <div
              key={player.id}
              className={`${bgClasses} rounded-lg p-5 border-2 ${borderClasses} transition-all`}
            >
              {/* Player name and badges */}
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-white font-semibold text-lg">{player.username}</span>
                  {index === 0 && (
                    <span className="text-xs bg-amber-400/20 text-amber-400 border border-amber-400/30 px-2 py-1 rounded-full font-semibold">
                      #{index + 1}
                    </span>
                  )}
                  {isLowest && (
                    <span className="flex items-center text-xs bg-amber-400/20 text-amber-400 border border-amber-400/30 px-2 py-1 rounded-full font-semibold">
                      <Crown className="w-3 h-3 mr-1" />
                      Lowest Hand
                    </span>
                  )}
                  {isEliminated && (
                    <span className="text-xs bg-red-500/20 text-red-400 border border-red-500/30 px-2 py-1 rounded-full font-semibold">
                      Eliminated
                    </span>
                  )}
                  {isZapZapCaller && (
                    <span className="flex items-center text-xs bg-purple-500/20 text-purple-400 border border-purple-500/30 px-2 py-1 rounded-full font-semibold">
                      <Zap className="w-3 h-3 mr-1" />
                      ZapZap
                    </span>
                  )}
                </div>
              </div>

              {/* Player hand */}
              <div className="mb-4">
                <p className="text-gray-400 text-sm mb-2">Hand:</p>
                <div className="flex flex-wrap gap-2">
                  {player.hand.map((cardId, idx) => (
                    <PlayingCard
                      key={`${cardId}-${idx}`}
                      cardId={cardId}
                      width={60}
                      selected={false}
                      disabled={true}
                    />
                  ))}
                </div>
              </div>

              {/* Scores */}
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-slate-800/50 rounded px-4 py-3">
                  <p className="text-gray-400 text-sm mb-1">This Round</p>
                  <p className="text-white font-bold text-xl">{player.score} pts</p>
                </div>
                <div className="bg-slate-800/50 rounded px-4 py-3">
                  <p className="text-gray-400 text-sm mb-1">Total Score</p>
                  <p className={`font-bold text-xl ${isEliminated ? 'text-red-400' : 'text-white'}`}>
                    {player.totalScore}
                  </p>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Eliminated players summary */}
      {eliminatedPlayers.length > 0 && (
        <div className="bg-red-900/30 border border-red-700 rounded-lg p-6 mb-8">
          <div className="flex items-center mb-4">
            <AlertTriangle className="w-5 h-5 text-red-400 mr-2" />
            <h3 className="text-lg font-semibold text-red-400">Eliminated Players</h3>
          </div>
          <div className="space-y-2">
            {eliminatedPlayers.map((player) => (
              <p key={player.id} className="text-red-200">
                <strong>{player.username}</strong> eliminated with {player.totalScore} points
              </p>
            ))}
          </div>
        </div>
      )}

      {/* Action button */}
      <div className="flex justify-center">
        {gameFinished ? (
          // Game finished - show Back to Parties button
          <button
            onClick={() => navigate('/parties')}
            className="flex items-center px-8 py-4 bg-green-500 hover:bg-green-600 text-white font-semibold rounded-lg transition-colors shadow-lg"
          >
            <Home className="w-5 h-5 mr-2" />
            Back to Parties
          </button>
        ) : (
          // Game continues - show Continue button
          <button
            onClick={onContinue}
            disabled={disabled}
            className="flex items-center px-8 py-4 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-60 disabled:cursor-not-allowed"
          >
            Continue to Next Round
            <ArrowRight className="w-5 h-5 ml-2" />
          </button>
        )}
      </div>
    </div>
  );
}

export default RoundEnd;
