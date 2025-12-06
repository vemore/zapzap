import { Users, User, Play, Skull } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import CardBack from './CardBack';

/**
 * PlayerTable component - displays all players in a horizontal row
 * @param {Object[]} players - Array of player objects with username, cardCount, score, isEliminated
 * @param {number} currentTurn - Index of player whose turn it is
 * @param {string} currentUserId - ID of the current user
 * @param {boolean} isGoldenScore - Whether the game is in Golden Score mode
 */
function PlayerTable({ players = [], currentTurn, currentUserId, isGoldenScore = false }) {
  if (players.length === 0) {
    return (
      <div className="bg-slate-800 rounded-lg shadow-xl p-4 sm:p-8 border border-slate-700 text-center">
        <Users className="w-8 h-8 sm:w-12 sm:h-12 text-gray-500 mx-auto mb-2 sm:mb-3" />
        <p className="text-gray-400 text-sm sm:text-base">Waiting for players...</p>
      </div>
    );
  }

  return (
    <div className="bg-slate-800/50 rounded-lg shadow-xl p-2 sm:p-4 border border-slate-700">
      {/* Horizontal scrollable container on mobile */}
      <div className="flex gap-2 sm:gap-4 overflow-x-auto pb-1 sm:pb-0 sm:flex-wrap sm:justify-center scrollbar-thin scrollbar-thumb-slate-600">
        {players.map((player, index) => (
          <PlayerCard
            key={player.userId || index}
            player={player}
            isCurrentUser={player.userId === currentUserId}
            isCurrentTurn={player.playerIndex === currentTurn && !player.isEliminated}
            isEliminated={player.isEliminated}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * PlayerCard component - displays a single player with card fan
 * Compact on mobile, expanded on desktop
 */
function PlayerCard({ player, isCurrentUser, isCurrentTurn, isEliminated = false }) {
  const cardCount = player.cardCount || 0;

  // Eliminated players have special styling
  if (isEliminated) {
    return (
      <motion.div
        className="bg-slate-900/80 rounded-lg p-2 sm:p-3 border-2 border-red-900/50 opacity-60 min-w-[90px] sm:min-w-[140px] flex-shrink-0"
        layout
      >
        {/* Player header - compact on mobile */}
        <div className="flex items-center justify-between mb-1 sm:mb-2">
          <div className="flex items-center">
            <Skull className="w-3 h-3 sm:w-4 sm:h-4 text-red-500 mr-1" />
            <span className="text-gray-500 font-semibold text-xs sm:text-sm truncate max-w-[60px] sm:max-w-[100px] line-through">
              {player.username}
            </span>
          </div>
          {isCurrentUser && (
            <span className="text-[10px] sm:text-xs bg-red-900/30 text-red-400 border border-red-900/50 px-1 sm:px-1.5 py-0.5 rounded-full">
              You
            </span>
          )}
        </div>

        {/* Eliminated indicator - hidden on mobile for space */}
        <div className="hidden sm:flex items-center justify-center text-red-500 text-xs font-semibold mb-2">
          <Skull className="w-3 h-3 mr-1" />
          ELIMINATED
        </div>

        {/* Compact card count on mobile, card fan on desktop */}
        <div className="flex justify-center items-center h-8 sm:h-16 sm:items-end mb-1 sm:mb-2">
          <span className="text-gray-600 text-xs">☠️</span>
        </div>

        {/* Score */}
        <div className="flex justify-center text-[10px] sm:text-xs">
          <span className="text-red-400">
            <span className="font-bold">{player.score}</span>
          </span>
        </div>
      </motion.div>
    );
  }

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
      className={`${bgClasses} rounded-lg p-2 sm:p-3 border-2 ${borderClasses} transition-all min-w-[90px] sm:min-w-[140px] flex-shrink-0`}
      layout
    >
      {/* Player header - compact on mobile */}
      <div className="flex items-center justify-between mb-1 sm:mb-2">
        <div className="flex items-center">
          <User className="w-3 h-3 sm:w-4 sm:h-4 text-gray-400 mr-1" />
          <span className="text-white font-semibold text-xs sm:text-sm truncate max-w-[50px] sm:max-w-[100px]">
            {player.username}
          </span>
        </div>
        {isCurrentUser && (
          <span className="text-[10px] sm:text-xs bg-amber-400/20 text-amber-400 border border-amber-400/30 px-1 sm:px-1.5 py-0.5 rounded-full">
            You
          </span>
        )}
      </div>

      {/* Turn indicator - icon only on mobile */}
      {isCurrentTurn && (
        <div className="flex items-center justify-center text-green-400 text-[10px] sm:text-xs font-semibold mb-1 sm:mb-2">
          <Play className="w-3 h-3 sm:mr-1" />
          <span className="hidden sm:inline">Playing</span>
        </div>
      )}

      {/* Card display - simple count on mobile, fan on desktop */}
      <div className="flex justify-center items-center sm:items-end h-8 sm:h-16 mb-1 sm:mb-2">
        {/* Mobile: simple card count display */}
        <div className="flex sm:hidden items-center gap-1">
          <span className="text-lg">🂠</span>
          <span className="text-white font-bold text-sm">{cardCount}</span>
        </div>
        {/* Desktop: card fan */}
        <div className="hidden sm:flex justify-center items-end">
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
      </div>

      {/* Card count and score - compact on mobile */}
      <div className="flex justify-between text-[10px] sm:text-xs">
        <span className="text-gray-400 hidden sm:inline">
          <span className="text-white font-medium">{cardCount}</span> cards
        </span>
        {player.score !== undefined && (
          <span className="text-gray-400 w-full sm:w-auto text-center sm:text-right">
            <span className="sm:hidden text-white font-medium">{player.score}</span>
            <span className="hidden sm:inline">Score: <span className="text-white font-medium">{player.score}</span></span>
          </span>
        )}
      </div>
    </motion.div>
  );
}

export default PlayerTable;
