/**
 * DeckPile - Displays the draw deck with card count
 *
 * @param {number} cardsRemaining - Number of cards left in deck
 * @param {Function} onClick - Callback when deck is clicked
 * @param {boolean} disabled - Whether drawing is disabled
 */
function DeckPile({ cardsRemaining = 0, onClick, disabled = false }) {
  return (
    <div className="deck-pile">
      <div className="deck-pile-label text-gray-400 text-sm mb-2 text-center">
        Draw Deck
      </div>
      <div
        className={`deck-card-wrapper flex flex-col items-center ${
          !disabled ? 'cursor-pointer hover:scale-105' : 'opacity-60'
        } transition-transform`}
        onClick={disabled ? undefined : onClick}
        role="button"
        tabIndex={disabled ? -1 : 0}
        aria-label={`Draw from deck (${cardsRemaining} cards remaining)`}
      >
        {/* Card back representation */}
        <div
          className={`deck-card bg-gradient-to-br from-blue-800 to-blue-900 border-2 ${
            !disabled ? 'border-blue-500 hover:border-blue-400' : 'border-gray-600'
          } rounded-lg shadow-lg flex items-center justify-center`}
          style={{ width: '70px', height: '98px' }}
        >
          <div className="text-center">
            <div className="text-2xl mb-1">🂠</div>
            <div className="text-white text-xs font-bold">{cardsRemaining}</div>
          </div>
        </div>
      </div>
      {!disabled && (
        <div className="text-center mt-2 text-xs text-gray-500">
          Click to draw
        </div>
      )}
    </div>
  );
}

export default DeckPile;
