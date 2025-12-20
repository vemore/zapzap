import { useState, useEffect } from 'react';
import { Users, User, Play, Skull } from 'lucide-react';
import { motion } from 'framer-motion';
import CardBack from './CardBack';

/**
 * PlayerTable component - displays all players in vertical rows
 * Format: <Name> - <score> : <card backs> (<count>)
 *
 * @param {Object[]} players - Array of player objects with username, cardCount, score, isEliminated
 * @param {number} currentTurn - Index of player whose turn it is
 * @param {string} currentUserId - ID of the current user
 * @param {boolean} isGoldenScore - Whether the game is in Golden Score mode
 * @param {number} startingPlayer - Index of the player who started this round
 */
function PlayerTable({ players = [], currentTurn, currentUserId, isGoldenScore = false, startingPlayer = 0 }) {
  if (players.length === 0) {
    return (
      <div className="bg-slate-800 rounded-lg shadow-xl p-4 sm:p-8 border border-slate-700 text-center">
        <Users className="w-8 h-8 sm:w-12 sm:h-12 text-gray-500 mx-auto mb-2 sm:mb-3" />
        <p className="text-gray-400 text-sm sm:text-base">Waiting for players...</p>
      </div>
    );
  }

  // Sort players by turn order starting from startingPlayer
  // The starting player appears first, then players follow in circular order
  const sortedPlayers = [...players].sort((a, b) => {
    const playerCount = players.length;
    // Calculate position relative to starting player (0 = starting player, 1 = next, etc.)
    const posA = (a.playerIndex - startingPlayer + playerCount) % playerCount;
    const posB = (b.playerIndex - startingPlayer + playerCount) % playerCount;
    return posA - posB;
  });

  return (
    <div className="bg-slate-800/50 rounded-lg shadow-xl border border-slate-700 overflow-hidden">
      <div className="divide-y divide-slate-700/50">
        {sortedPlayers.map((player) => (
          <PlayerRow
            key={player.userId}
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
 * PlayerRow component - displays a single player in a horizontal row
 * Format: [PlayIcon] <Name> [You] - <Score> : <CardBacks> (<count>)
 */
function PlayerRow({ player, isCurrentUser, isCurrentTurn, isEliminated = false }) {
  const cardCount = player.cardCount || 0;

  // Build row classes based on state
  // Mobile: h-8 (32px), Desktop: h-10 (40px)
  let rowClasses = "flex items-center px-2 py-0.5 sm:px-3 sm:py-1.5 h-8 sm:h-10 transition-all";

  if (isCurrentTurn) {
    rowClasses += " border-l-4 border-green-400 bg-green-900/20";
  } else if (isCurrentUser && !isEliminated) {
    rowClasses += " bg-amber-900/10 border-l-4 border-transparent";
  } else {
    rowClasses += " border-l-4 border-transparent";
  }

  if (isEliminated) {
    rowClasses += " opacity-50 bg-red-900/10";
  }

  return (
    <motion.div className={rowClasses} layout>
      {/* Left section: Turn indicator + Name + You badge */}
      <div className="flex items-center flex-shrink-0 min-w-0">
        {/* Animated Play icon for current turn */}
        {isCurrentTurn && (
          <motion.div
            className="mr-1 sm:mr-1.5 flex-shrink-0"
            animate={{ scale: [1, 1.15, 1] }}
            transition={{ duration: 1.2, repeat: Infinity, ease: "easeInOut" }}
          >
            <Play className="w-3 h-3 sm:w-4 sm:h-4 text-green-400 fill-green-400" />
          </motion.div>
        )}

        {/* Skull icon for eliminated players */}
        {isEliminated && (
          <Skull className="w-3 h-3 sm:w-4 sm:h-4 text-red-500 mr-1 sm:mr-1.5 flex-shrink-0" />
        )}

        {/* Player icon (only when not current turn and not eliminated) */}
        {!isCurrentTurn && !isEliminated && (
          <User className="w-3 h-3 sm:w-4 sm:h-4 text-gray-400 mr-1 sm:mr-1.5 flex-shrink-0" />
        )}

        {/* Player name */}
        <span
          className={`text-xs sm:text-sm font-semibold truncate max-w-[80px] sm:max-w-[120px] ${
            isEliminated ? "text-gray-500 line-through" : "text-white"
          }`}
        >
          {player.username}
        </span>

        {/* You badge */}
        {isCurrentUser && (
          <span className="ml-1 sm:ml-1.5 text-[9px] sm:text-xs bg-amber-400/20 text-amber-400 border border-amber-400/30 px-1 py-0 sm:py-0.5 rounded-full flex-shrink-0">
            You
          </span>
        )}
      </div>

      {/* Separator */}
      <span className="text-gray-500 mx-1 sm:mx-2 flex-shrink-0 text-[10px] sm:text-sm">-</span>

      {/* Score */}
      <span
        className={`text-[10px] sm:text-sm font-medium flex-shrink-0 ${
          isEliminated ? "text-red-400" : "text-white"
        }`}
      >
        {player.score}
      </span>

      {/* Separator */}
      <span className="text-gray-500 mx-1 sm:mx-2 flex-shrink-0 text-[10px] sm:text-sm">:</span>

      {/* Card backs + count - takes remaining space, aligned to right */}
      <div className="flex items-center flex-1 justify-end overflow-hidden">
        {!isEliminated ? (
          <CardBacks cardCount={cardCount} />
        ) : (
          <span className="text-gray-500 text-xs">--</span>
        )}
      </div>
    </motion.div>
  );
}

/**
 * CardBacks component - displays card back images in a row
 * Shows a limited number of cards with count in parentheses
 */
function CardBacks({ cardCount }) {
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const updateIsMobile = () => {
      setIsMobile(window.innerWidth < 640);
    };

    updateIsMobile();
    window.addEventListener('resize', updateIsMobile);
    return () => window.removeEventListener('resize', updateIsMobile);
  }, []);

  const maxVisible = isMobile ? 5 : 8;
  const displayCount = Math.min(cardCount, maxVisible);
  const cardSize = isMobile ? "xxs" : "xs";

  return (
    <div className="flex items-center">
      {/* Card backs - side by side, no overlap */}
      <div className="flex items-center gap-0.5">
        {Array(displayCount).fill(0).map((_, i) => (
          <CardBack key={i} size={cardSize} />
        ))}
      </div>

      {/* Card count in parentheses */}
      <span className="text-gray-400 text-[10px] sm:text-xs ml-1">
        ({cardCount})
      </span>
    </div>
  );
}

export default PlayerTable;
