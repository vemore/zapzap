import { useMemo } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Layers, Download, ArrowRight } from 'lucide-react';
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
        return {
          text: `${playerName} drew from deck`,
          icon: <Download className="w-4 h-4" />
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
    <div className="bg-gradient-to-b from-green-900/40 to-green-800/30 rounded-xl p-6 border border-green-700/50 shadow-inner">
      {/* Action message */}
      <AnimatePresence mode="wait">
        {actionMessage && (
          <motion.div
            key={lastAction?.timestamp || 'action'}
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="flex items-center justify-center gap-2 mb-4 text-green-300 text-sm font-medium"
          >
            {actionMessage.icon}
            <span>{actionMessage.text}</span>
            {actionMessage.cardId !== undefined && lastAction?.source === 'played' && (
              <span className="inline-block ml-2 scale-75">
                <PlayingCard cardId={actionMessage.cardId} width={50} disabled />
              </span>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Cards played this turn */}
      {cardsPlayed.length > 0 && (
        <div className="mb-6">
          <div className="text-xs text-gray-400 mb-2 text-center">Cards played this turn</div>
          <div className="flex justify-center gap-2 flex-wrap">
            <AnimatePresence mode="popLayout">
              {cardsPlayed.map((cardId, i) => (
                <motion.div
                  key={`played-${cardId}-${i}`}
                  initial={{ y: 100, opacity: 0, rotate: Math.random() * 20 - 10, scale: 0.5 }}
                  animate={{ y: 0, opacity: 1, rotate: 0, scale: 1 }}
                  exit={{ y: -50, opacity: 0, scale: 0.5 }}
                  transition={{
                    type: 'spring',
                    damping: 15,
                    stiffness: 200,
                    delay: i * 0.1
                  }}
                >
                  <PlayingCard cardId={cardId} width={70} disabled />
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </div>
      )}

      {/* Separator */}
      <div className="border-t border-green-700/50 my-4" />

      {/* Discard pile (last cards played) */}
      <div>
        <div className="flex items-center justify-center gap-2 text-xs text-gray-400 mb-2">
          <Layers className="w-3 h-3" />
          <span>Discard pile ({lastCardsPlayed.length} cards)</span>
        </div>
        {lastCardsPlayed.length > 0 ? (
          <div className="flex justify-center gap-2 flex-wrap">
            <AnimatePresence mode="popLayout">
              {lastCardsPlayed.map((cardId, i) => (
                <motion.div
                  key={`discard-${cardId}-${i}`}
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.5, y: 50 }}
                  transition={{ delay: i * 0.05 }}
                  whileHover={{ scale: 1.05, y: -5 }}
                  whileTap={{ scale: 0.95 }}
                >
                  <PlayingCard
                    cardId={cardId}
                    width={60}
                    onClick={() => onDiscardSelect?.(cardId)}
                    selected={selectedDiscardCard === cardId}
                    disabled={!onDiscardSelect}
                  />
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        ) : (
          <div className="text-center text-gray-500 text-sm py-4">
            No cards in discard pile
          </div>
        )}
      </div>
    </div>
  );
}

export default TableArea;
