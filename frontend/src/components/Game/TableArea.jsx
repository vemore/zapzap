import { useMemo, useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Layers, Download, ArrowRight, Shuffle } from 'lucide-react';
import PlayingCard from './PlayingCard';

/**
 * TableArea - Central game table showing played cards and action messages
 *
 * @param {number[]} cardsPlayed - Cards played this turn
 * @param {number[]} lastCardsPlayed - Cards from previous turn (discard pile)
 * @param {Object} lastAction - Last action { type, playerIndex, source?, cardId?, cardIds? }
 * @param {Object[]} players - Players array with username by playerIndex
 * @param {number} currentTurn - Current turn player index
 * @param {Function} onDiscardSelect - Handler when a discard card is selected
 * @param {number} selectedDiscardCard - Currently selected discard card
 */
function TableArea({
  cardsPlayed = [],
  lastCardsPlayed = [],
  lastAction = null,
  players = [],
  currentTurn,
  onDiscardSelect,
  selectedDiscardCard
}) {
  // Get player name by index
  const getPlayerName = (playerIndex) => {
    const player = players.find(p => p.playerIndex === playerIndex);
    return player?.username || `Player ${playerIndex + 1}`;
  };

  // Track when deck was reshuffled for animation
  const [showReshuffle, setShowReshuffle] = useState(false);

  // Trigger reshuffle animation when deck is reshuffled
  useEffect(() => {
    if (lastAction?.deckReshuffled) {
      setShowReshuffle(true);
      const timer = setTimeout(() => setShowReshuffle(false), 2500);
      return () => clearTimeout(timer);
    }
  }, [lastAction?.timestamp]);

  // Build action message
  const actionMessage = useMemo(() => {
    if (!lastAction) return null;

    const playerName = getPlayerName(lastAction.playerIndex);

    if (lastAction.type === 'play') {
      const cardCount = lastAction.cardIds?.length || cardsPlayed.length;
      return {
        text: `${playerName} played ${cardCount} card${cardCount > 1 ? 's' : ''}`,
        icon: <ArrowRight className="w-4 h-4" />
      };
    }

    if (lastAction.type === 'draw') {
      if (lastAction.source === 'deck') {
        // Check if deck was reshuffled during this draw
        const reshuffleText = lastAction.deckReshuffled
          ? ' (deck reshuffled!)'
          : '';
        return {
          text: `${playerName} drew from deck${reshuffleText}`,
          icon: lastAction.deckReshuffled ? <Shuffle className="w-4 h-4" /> : <Download className="w-4 h-4" />,
          deckReshuffled: lastAction.deckReshuffled
        };
      } else {
        return {
          text: `${playerName} took a card from discard`,
          icon: <Layers className="w-4 h-4" />,
          cardId: lastAction.cardId
        };
      }
    }

    return null;
  }, [lastAction, players, cardsPlayed]);

  return (
    <div className="relative bg-gradient-to-b from-green-900/40 to-green-800/30 rounded-lg sm:rounded-xl p-2 sm:p-4 border border-green-700/50 shadow-inner">
      {/* Reshuffle animation overlay */}
      <AnimatePresence>
        {showReshuffle && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.8 }}
            className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none"
          >
            <motion.div
              className="bg-amber-500/90 text-white px-3 py-2 sm:px-6 sm:py-3 rounded-lg shadow-lg flex items-center gap-2 sm:gap-3"
              animate={{
                rotate: [0, -5, 5, -5, 5, 0],
              }}
              transition={{
                duration: 0.5,
                repeat: 2,
                ease: "easeInOut"
              }}
            >
              <motion.div
                animate={{ rotate: 360 }}
                transition={{ duration: 0.8, repeat: 2, ease: "linear" }}
              >
                <Shuffle className="w-4 h-4 sm:w-6 sm:h-6" />
              </motion.div>
              <span className="font-bold text-sm sm:text-lg">Reshuffled!</span>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Action message - compact on mobile */}
      <AnimatePresence mode="wait">
        {actionMessage && (
          <motion.div
            key={lastAction?.timestamp || 'action'}
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className={`flex items-center justify-center gap-1 sm:gap-2 mb-2 sm:mb-3 text-xs sm:text-sm font-medium ${
              actionMessage.deckReshuffled ? 'text-amber-400' : 'text-green-300'
            }`}
          >
            {actionMessage.icon}
            <span className="truncate max-w-[200px] sm:max-w-none">{actionMessage.text}</span>
            {actionMessage.cardId !== undefined && lastAction?.source === 'played' && (
              <span className="hidden sm:inline-block ml-2 scale-75">
                <PlayingCard cardId={actionMessage.cardId} width={40} disabled />
              </span>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Mobile: Horizontal layout for cards played and discard pile */}
      <div className="flex flex-row sm:flex-col gap-2 sm:gap-0">
        {/* Cards played this turn */}
        <div className={`flex-1 ${cardsPlayed.length > 0 ? '' : 'hidden sm:block'}`}>
          {cardsPlayed.length > 0 && (
            <div className="sm:mb-4">
              <div className="text-[10px] sm:text-xs text-gray-400 mb-1 sm:mb-2 text-center">Played</div>
              <div className="flex justify-center gap-1 sm:gap-2 flex-wrap">
                <AnimatePresence mode="popLayout">
                  {cardsPlayed.map((cardId, i) => (
                    <motion.div
                      key={`played-${cardId}-${i}`}
                      initial={{ y: 50, opacity: 0, scale: 0.5 }}
                      animate={{ y: 0, opacity: 1, scale: 1 }}
                      exit={{ y: -30, opacity: 0, scale: 0.5 }}
                      transition={{
                        type: 'spring',
                        damping: 15,
                        stiffness: 200,
                        delay: i * 0.05
                      }}
                    >
                      <PlayingCard cardId={cardId} width={45} disabled />
                    </motion.div>
                  ))}
                </AnimatePresence>
              </div>
            </div>
          )}
        </div>

        {/* Separator - hidden on mobile */}
        <div className="hidden sm:block border-t border-green-700/50 my-3" />

        {/* Discard pile (last cards played) */}
        <div className="flex-1">
          <div className="flex items-center justify-center gap-1 sm:gap-2 text-[10px] sm:text-xs text-gray-400 mb-1 sm:mb-2">
            <Layers className="w-2.5 h-2.5 sm:w-3 sm:h-3" />
            <span>Discard ({lastCardsPlayed.length})</span>
          </div>
          {lastCardsPlayed.length > 0 ? (
            <div className="flex justify-center gap-1 sm:gap-2 flex-wrap">
              <AnimatePresence mode="popLayout">
                {lastCardsPlayed.map((cardId, i) => (
                  <motion.div
                    key={`discard-${cardId}-${i}`}
                    initial={{ opacity: 0, scale: 0.8 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0, scale: 0.5, y: 30 }}
                    transition={{ delay: i * 0.03 }}
                    whileHover={{ scale: 1.05, y: -3 }}
                    whileTap={{ scale: 0.95 }}
                  >
                    <PlayingCard
                      cardId={cardId}
                      width={45}
                      onClick={() => onDiscardSelect?.(selectedDiscardCard === cardId ? null : cardId)}
                      selected={selectedDiscardCard === cardId}
                      disabled={!onDiscardSelect}
                    />
                  </motion.div>
                ))}
              </AnimatePresence>
            </div>
          ) : (
            <div className="text-center text-gray-500 text-[10px] sm:text-sm py-2 sm:py-4">
              Empty
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default TableArea;
