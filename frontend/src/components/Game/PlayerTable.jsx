import { Users, User, Play } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import CardBack from './CardBack';

/**
 * PlayerTable component - displays all players in a horizontal row
 * @param {Object[]} players - Array of player objects with username, cardCount, score
 * @param {number} currentTurn - Index of player whose turn it is
 * @param {string} currentUserId - ID of the current user
 */
function PlayerTable({ players = [], currentTurn, currentUserId }) {
  if (players.length === 0) {
    return (
      <div className="bg-slate-800 rounded-lg shadow-xl p-8 border border-slate-700 text-center">
        <Users className="w-12 h-12 text-gray-500 mx-auto mb-3" />
        <p className="text-gray-400">Waiting for players...</p>
      </div>
    );
  }

  return (
    <div className="bg-slate-800/50 rounded-lg shadow-xl p-4 border border-slate-700">
      <div className="flex flex-wrap justify-center gap-4">
        {players.map((player, index) => (
          <PlayerCard
            key={player.userId || index}
            player={player}
            isCurrentUser={player.userId === currentUserId}
            isCurrentTurn={player.playerIndex === currentTurn}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * PlayerCard component - displays a single player with card fan
 */
function PlayerCard({ player, isCurrentUser, isCurrentTurn }) {
  const cardCount = player.cardCount || 0;

  const borderClasses = isCurrentUser
    ? 'border-amber-400 ring-2 ring-amber-400/30'
    : isCurrentTurn
    ? 'border-green-400 ring-2 ring-green-400/30 animate-pulse'
    : 'border-slate-600';

  const bgClasses = isCurrentTurn
    ? 'bg-green-900/30'
    : 'bg-slate-700/50';

  return (
    <motion.div
      className={`${bgClasses} rounded-lg p-3 border-2 ${borderClasses} transition-all min-w-[140px]`}
      layout
    >
      {/* Player header */}
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center">
          <User className="w-4 h-4 text-gray-400 mr-1" />
          <span className="text-white font-semibold text-sm truncate max-w-[100px]">
            {player.username}
          </span>
        </div>
        {isCurrentUser && (
          <span className="text-xs bg-amber-400/20 text-amber-400 border border-amber-400/30 px-1.5 py-0.5 rounded-full">
            You
          </span>
        )}
      </div>

      {/* Turn indicator */}
      {isCurrentTurn && (
        <div className="flex items-center justify-center text-green-400 text-xs font-semibold mb-2">
          <Play className="w-3 h-3 mr-1" />
          Playing
        </div>
      )}

      {/* Card fan */}
      <div className="flex justify-center items-end h-16 mb-2">
        <AnimatePresence mode="popLayout">
          {Array(Math.min(cardCount, 7)).fill(0).map((_, i) => (
            <motion.div
              key={`card-${i}`}
              className="card-in-fan"
              style={{
                marginLeft: i > 0 ? '-20px' : '0',
                transform: `rotate(${(i - Math.min(cardCount, 7) / 2) * 5}deg)`,
                transformOrigin: 'bottom center',
                zIndex: i
              }}
              initial={{ opacity: 0, y: -20, scale: 0.8 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 20, scale: 0.5 }}
              transition={{ delay: i * 0.05, duration: 0.2 }}
            >
              <CardBack size="sm" />
            </motion.div>
          ))}
        </AnimatePresence>
        {cardCount > 7 && (
          <span className="text-xs text-gray-400 ml-1">+{cardCount - 7}</span>
        )}
      </div>

      {/* Card count and score */}
      <div className="flex justify-between text-xs">
        <span className="text-gray-400">
          <span className="text-white font-medium">{cardCount}</span> cards
        </span>
        {player.score !== undefined && (
          <span className="text-gray-400">
            Score: <span className="text-white font-medium">{player.score}</span>
          </span>
        )}
      </div>
    </motion.div>
  );
}

export default PlayerTable;
