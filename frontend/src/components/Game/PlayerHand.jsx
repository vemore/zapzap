import { useState, useEffect } from 'react';
import { X, Sparkles } from 'lucide-react';
import { getCardName, getCardSuit, SUIT_SYMBOLS } from '../../utils/cards';
import { getHandValueDisplay, isZapZapEligible } from '../../utils/scoring';

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

      {/* Cards container */}
      <div className="flex flex-wrap gap-3 mb-6">
        {hand.map((cardId, index) => (
          <Card
            key={`${cardId}-${index}`}
            cardId={cardId}
            selected={selectedCards.includes(cardId)}
            onClick={() => handleCardClick(cardId)}
            disabled={disabled}
          />
        ))}
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

/**
 * Card component - displays a single card
 */
function Card({ cardId, selected, onClick, disabled }) {
  const suit = getCardSuit(cardId);
  const name = getCardName(cardId);
  const isRed = suit === 'hearts' || suit === 'diamonds';
  const isJoker = cardId >= 52;

  const baseClasses = "w-20 h-28 rounded-lg border-2 shadow-lg transition-all transform hover:scale-105 hover:-translate-y-1";
  const colorClasses = isRed ? "text-red-500" : "text-slate-900";
  const bgClasses = isJoker
    ? "bg-gradient-to-br from-amber-400 to-amber-600 border-amber-500"
    : "bg-white border-gray-300";
  const selectedClasses = selected
    ? "border-amber-400 ring-4 ring-amber-400/50 -translate-y-2 scale-110"
    : "";
  const disabledClasses = disabled ? "opacity-50 cursor-not-allowed" : "cursor-pointer";

  return (
    <button
      className={`${baseClasses} ${bgClasses} ${selectedClasses} ${disabledClasses}`}
      onClick={onClick}
      disabled={disabled}
      aria-label={`Card: ${name}`}
    >
      <div className="flex flex-col items-center justify-between h-full p-2">
        <div className={`text-2xl font-bold ${isJoker ? 'text-white' : colorClasses}`}>
          {name.slice(0, -1) || '🃏'}
        </div>
        <div className={`text-3xl ${isJoker ? 'text-white' : colorClasses}`}>
          {isJoker ? '🃏' : SUIT_SYMBOLS[suit]}
        </div>
        <div className={`text-2xl font-bold ${isJoker ? 'text-white' : colorClasses}`}>
          {name.slice(0, -1) || '🃏'}
        </div>
      </div>
    </button>
  );
}

export default PlayerHand;
