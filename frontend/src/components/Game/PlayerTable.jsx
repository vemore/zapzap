import { Users, User, Play } from 'lucide-react';

/**
 * PlayerTable component - displays all players at the table
 * @param {Object[]} players - Array of player objects
 * @param {string} currentTurnId - ID of player whose turn it is
 * @param {string} currentUserId - ID of the current user
 */
function PlayerTable({ players = [], currentTurnId, currentUserId }) {
  if (players.length === 0) {
    return (
      <div className="bg-slate-800 rounded-lg shadow-xl p-8 border border-slate-700 text-center">
        <Users className="w-12 h-12 text-gray-500 mx-auto mb-3" />
        <p className="text-gray-400">Waiting for players...</p>
      </div>
    );
  }

  return (
    <div className="bg-slate-800 rounded-lg shadow-xl p-6 border border-slate-700">
      <div className="flex items-center mb-4">
        <Users className="w-5 h-5 text-amber-400 mr-2" />
        <h3 className="text-lg font-semibold text-white">Players</h3>
      </div>
      <div className="space-y-3">
        {players.map((player) => (
          <PlayerCard
            key={player.id}
            player={player}
            isCurrentUser={player.id === currentUserId}
            isCurrentTurn={player.id === currentTurnId}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * PlayerCard component - displays a single player
 */
function PlayerCard({ player, isCurrentUser, isCurrentTurn }) {
  const borderClasses = isCurrentUser
    ? 'border-amber-400 ring-2 ring-amber-400/30'
    : isCurrentTurn
    ? 'border-green-400 ring-2 ring-green-400/30'
    : 'border-slate-600';

  const bgClasses = isCurrentTurn
    ? 'bg-green-900/20'
    : 'bg-slate-700';

  return (
    <div className={`${bgClasses} rounded-lg p-4 border-2 ${borderClasses} transition-all`}>
      {/* Player header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center">
          <User className="w-4 h-4 text-gray-400 mr-2" />
          <span className="text-white font-semibold">
            {player.username}
            {isCurrentUser && (
              <span className="ml-2 text-xs bg-amber-400/20 text-amber-400 border border-amber-400/30 px-2 py-0.5 rounded-full">
                You
              </span>
            )}
          </span>
        </div>
        {isCurrentTurn && (
          <div className="flex items-center text-green-400 text-sm font-semibold">
            <Play className="w-4 h-4 mr-1 animate-pulse" />
            Playing
          </div>
        )}
      </div>

      {/* Player stats */}
      <div className="grid grid-cols-2 gap-3">
        <div className="flex items-center justify-between bg-slate-800/50 rounded px-3 py-2">
          <span className="text-gray-400 text-sm">Cards:</span>
          <span className="text-white font-medium">
            {player.cardCount}
          </span>
        </div>

        {player.score !== undefined && (
          <div className="flex items-center justify-between bg-slate-800/50 rounded px-3 py-2">
            <span className="text-gray-400 text-sm">Score:</span>
            <span className="text-white font-medium">{player.score}</span>
          </div>
        )}
      </div>
    </div>
  );
}

export default PlayerTable;
