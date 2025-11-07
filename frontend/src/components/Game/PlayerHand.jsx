import { useState, useEffect } from 'react';
import { getCardName, getCardSuit, SUIT_SYMBOLS } from '../../utils/cards';
import { getHandValueDisplay, isZapZapEligible } from '../../utils/scoring';
import './PlayerHand.css';

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
      <div className="player-hand empty">
        <p>No cards in hand</p>
      </div>
    );
  }

  return (
    <div className="player-hand">
      <div className="hand-info">
        <span className="card-count">
          {hand.length} {hand.length === 1 ? 'card' : 'cards'}
        </span>
        <span className="hand-values">
          Eligibility: {handValues.eligibility} | Penalty: {handValues.penalty}
        </span>
        {zapZapEligible && (
          <span className="zapzap-indicator">✨ ZapZap Eligible!</span>
        )}
      </div>

      <div className="cards-container">
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

      <div className="hand-actions">
        <button
          onClick={handleClear}
          disabled={disabled || selectedCards.length === 0}
          className="clear-button"
        >
          Clear Selection
        </button>
        {selectedCards.length > 0 && (
          <span className="selection-count">
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

  const className = [
    'card',
    selected && 'selected',
    isRed && 'red',
    isJoker && 'joker',
    disabled && 'disabled',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <button
      className={className}
      onClick={onClick}
      disabled={disabled}
      aria-label={`Card: ${name}`}
    >
      <div className="card-content">
        <div className="card-rank">{name.slice(0, -1) || '🃏'}</div>
        <div className="card-suit">
          {isJoker ? '🃏' : SUIT_SYMBOLS[suit]}
        </div>
      </div>
    </button>
  );
}

export default PlayerHand;
