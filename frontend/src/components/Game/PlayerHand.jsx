import { useState, useEffect } from 'react';
import { X, Sparkles } from 'lucide-react';
import { getHandValueDisplay, isZapZapEligible } from '../../utils/scoring';
import CardFan from './CardFan';

/**
 * PlayerHand component - displays player's cards with selection
 * @param {number[]} hand - Array of card IDs
 * @param {Function} onCardsSelected - Callback when selection changes
 * @param {boolean} disabled - Disable card selection
 * @param {number} deckSize - Number of cards remaining in deck (optional, for integrated deck display)
 * @param {Function} onDrawFromDeck - Callback to draw from deck (optional)
 * @param {boolean} canDrawFromDeck - Whether drawing from deck is allowed (optional)
 */
function PlayerHand({ hand = [], onCardsSelected, disabled = false, deckSize, onDrawFromDeck, canDrawFromDeck = false }) {
  const [selectedCards, setSelectedCards] = useState([]);

  // Calculate hand values
  const handValues = getHandValueDisplay(hand);
  const zapZapEligible = isZapZapEligible(hand);

  // Toggle card selection
  const handleCardClick = (cardId) => {
    if (disabled) return;

    setSelectedCards((prev) => {
      const newSelection = prev.includes(cardId)
        ? prev.filter((c) => c !== cardId) // Deselect
        : [...prev, cardId]; // Select

      onCardsSelected(newSelection);
      return newSelection;
    });
  };

  // Clear selection
  const handleClear = () => {
    setSelectedCards([]);
    onCardsSelected([]);
  };

  // Reset selection when hand changes
  useEffect(() => {
    setSelectedCards([]);
  }, [hand.length]);

  if (hand.length === 0) {
    return (
      <div className="bg-slate-800 rounded-lg shadow-xl p-6 sm:p-12 border border-slate-700 text-center">
        <p className="text-gray-400 text-sm sm:text-lg">No cards in hand</p>
      </div>
    );
  }

  return (
    <div className="bg-slate-800 rounded-lg shadow-xl p-2 sm:p-4 border border-slate-700 flex flex-col h-full">
      {/* Hand info - compact on mobile */}
      <div className="flex flex-wrap items-center justify-between mb-2 sm:mb-4 gap-1 sm:gap-4">
        <div className="flex items-center gap-2 sm:gap-4">
          <span className="text-white font-semibold text-sm sm:text-base">
            {hand.length} <span className="hidden sm:inline">{hand.length === 1 ? 'card' : 'cards'}</span>
          </span>
          <span className="text-gray-400 text-[10px] sm:text-sm">
            <span className="text-white">{handValues.eligibility}</span>
            <span className="mx-1">|</span>
            <span className="text-white">{handValues.penalty}</span>
          </span>
        </div>
        <div className="flex items-center gap-2">
          {zapZapEligible && (
            <div className="flex items-center bg-amber-400/20 border border-amber-400/30 rounded-full px-2 py-1 sm:px-4 sm:py-2">
              <Sparkles className="w-3 h-3 sm:w-4 sm:h-4 text-amber-400 sm:mr-2 animate-pulse" />
              <span className="hidden sm:inline text-amber-400 font-semibold text-sm">ZapZap Eligible!</span>
            </div>
          )}
          {/* Integrated deck indicator on mobile */}
          {deckSize !== undefined && (
            <button
              onClick={onDrawFromDeck}
              disabled={!canDrawFromDeck}
              className={`sm:hidden flex items-center gap-1 px-2 py-1 rounded-lg border transition-all ${
                canDrawFromDeck
                  ? 'bg-blue-600 border-blue-500 text-white hover:bg-blue-700'
                  : 'bg-slate-700 border-slate-600 text-gray-400 opacity-50'
              }`}
            >
              <span className="text-sm">🂠</span>
              <span className="text-xs font-bold">{deckSize}</span>
            </button>
          )}
        </div>
      </div>

      {/* Cards container - Fan layout, flexible height */}
      <div className="flex-1 flex items-center justify-center min-h-0 overflow-hidden">
        <CardFan
          cards={hand}
          selectedCards={selectedCards}
          onCardClick={handleCardClick}
          disabled={disabled}
          cardWidth={70}
          mobileCardWidth={50}
          maxSpreadAngle={75}
        />
      </div>

      {/* Hand actions - compact on mobile */}
      <div className="flex items-center justify-between mt-2 sm:mt-4">
        <button
          onClick={handleClear}
          disabled={disabled || selectedCards.length === 0}
          className="flex items-center px-2 py-1 sm:px-4 sm:py-2 bg-slate-700 hover:bg-slate-600 text-white font-semibold rounded-lg transition-colors disabled:opacity-40 disabled:cursor-not-allowed text-xs sm:text-base"
        >
          <X className="w-3 h-3 sm:w-4 sm:h-4 sm:mr-2" />
          <span className="hidden sm:inline">Clear Selection</span>
          <span className="sm:hidden ml-1">Clear</span>
        </button>
        {selectedCards.length > 0 && (
          <span className="text-amber-400 font-semibold text-xs sm:text-base">
            {selectedCards.length} <span className="hidden sm:inline">selected</span>
          </span>
        )}
      </div>
    </div>
  );
}

export default PlayerHand;
