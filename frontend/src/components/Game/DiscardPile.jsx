import PlayingCard from './PlayingCard';

/**
 * DiscardPile - Displays the cards from the previous player's turn
 * These cards are available to draw from
 *
 * @param {number[]} cards - Array of card IDs (lastCardsPlayed)
 * @param {number|null} selectedCard - Currently selected card ID
 * @param {Function} onCardSelect - Callback when a card is selected
 * @param {boolean} disabled - Whether selection is disabled
 */
function DiscardPile({ cards = [], selectedCard = null, onCardSelect, disabled = false }) {
  if (cards.length === 0) {
    return (
      <div className="discard-pile empty">
        <div className="discard-pile-placeholder">
          <span className="text-gray-500 text-sm">No cards to draw</span>
        </div>
      </div>
    );
  }

  const handleCardClick = (cardId) => {
    if (disabled) return;

    // Toggle selection: if already selected, deselect; otherwise select
    if (selectedCard === cardId) {
      onCardSelect(null);
    } else {
      onCardSelect(cardId);
    }
  };

  return (
    <div className="discard-pile">
      <div className="discard-pile-label text-gray-400 text-sm mb-2 text-center">
        Previous Player's Cards
      </div>
      <div className="discard-pile-cards flex justify-center gap-2">
        {cards.map((cardId, index) => (
          <div
            key={`discard-${cardId}-${index}`}
            className={`discard-card-wrapper transition-transform ${
              selectedCard === cardId ? 'ring-2 ring-green-400 rounded-lg scale-110' : ''
            } ${!disabled ? 'hover:scale-105 cursor-pointer' : 'opacity-60'}`}
          >
            <PlayingCard
              cardId={cardId}
              selected={selectedCard === cardId}
              onClick={() => handleCardClick(cardId)}
              disabled={disabled}
              width={70}
            />
          </div>
        ))}
      </div>
      {!disabled && cards.length > 0 && (
        <div className="text-center mt-2 text-xs text-gray-500">
          Click a card to select it for drawing
        </div>
      )}
    </div>
  );
}

export default DiscardPile;
