import { useState, useEffect } from 'react';
import { X, Sparkles } from 'lucide-react';
import { getHandValueDisplay, isZapZapEligible } from '../../utils/scoring';
import CardFan from './CardFan';

/**
 * PlayerHand component - displays player's cards with selection
 * @param {number[]} hand - Array of card IDs
 * @param {Function} onCardsSelected - Callback when selection changes
 * @param {boolean} disabled - Disable card selection
 */
function PlayerHand({ hand = [], onCardsSelected, disabled = false }) {
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
      <div className="bg-slate-800 rounded-lg shadow-xl p-12 border border-slate-700 text-center">
        <p className="text-gray-400 text-lg">No cards in hand</p>
      </div>
    );
  }

  return (
    <div className="bg-slate-800 rounded-lg shadow-xl p-6 border border-slate-700">
      {/* Hand info */}
      <div className="flex flex-wrap items-center justify-between mb-6 gap-4">
        <div className="flex items-center gap-4">
          <span className="text-white font-semibold">
            {hand.length} {hand.length === 1 ? 'card' : 'cards'}
          </span>
          <span className="text-gray-400 text-sm">
            Eligibility: <span className="text-white">{handValues.eligibility}</span> |
            Penalty: <span className="text-white">{handValues.penalty}</span>
          </span>
        </div>
        {zapZapEligible && (
          <div className="flex items-center bg-amber-400/20 border border-amber-400/30 rounded-full px-4 py-2">
            <Sparkles className="w-4 h-4 text-amber-400 mr-2 animate-pulse" />
            <span className="text-amber-400 font-semibold text-sm">ZapZap Eligible!</span>
          </div>
        )}
      </div>

      {/* Cards container - Fan layout */}
      <div className="flex justify-center mb-6">
        <CardFan
          cards={hand}
          selectedCards={selectedCards}
          onCardClick={handleCardClick}
          disabled={disabled}
          cardWidth={110}
          maxSpreadAngle={90}
        />
      </div>

      {/* Hand actions */}
      <div className="flex items-center justify-between">
        <button
          onClick={handleClear}
          disabled={disabled || selectedCards.length === 0}
          className="flex items-center px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white font-semibold rounded-lg transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
        >
          <X className="w-4 h-4 mr-2" />
          Clear Selection
        </button>
        {selectedCards.length > 0 && (
          <span className="text-amber-400 font-semibold">
            {selectedCards.length} selected
          </span>
        )}
      </div>
    </div>
  );
}

export default PlayerHand;
