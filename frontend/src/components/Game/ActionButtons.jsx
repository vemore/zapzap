import './ActionButtons.css';

/**
 * ActionButtons component - Play, Draw, ZapZap actions
 * @param {number[]} selectedCards - Currently selected cards
 * @param {Function} onPlay - Play selected cards
 * @param {Function} onDraw - Draw a card
 * @param {Function} onZapZap - Call ZapZap
 * @param {string} currentAction - Current required action ('play' or 'draw')
 * @param {boolean} isMyTurn - Is it the current player's turn
 * @param {boolean} zapZapEligible - Can call ZapZap
 * @param {string} invalidPlay - Invalid play reason
 */
function ActionButtons({
  selectedCards = [],
  onPlay,
  onDraw,
  onZapZap,
  currentAction = 'play',
  isMyTurn = false,
  zapZapEligible = false,
  invalidPlay = null,
}) {
  // Play button logic
  const canPlay = isMyTurn && selectedCards.length > 0 && !invalidPlay;

  // Draw button logic
  const canDraw = isMyTurn && currentAction === 'draw';

  // ZapZap button logic
  const canZapZap = isMyTurn && zapZapEligible;

  return (
    <div className="action-buttons">
      <div className="turn-indicator">
        {isMyTurn ? (
          <span className="my-turn">✨ Your Turn - {currentAction === 'draw' ? 'Draw a card' : 'Play cards or Draw'}</span>
        ) : (
          <span className="waiting">⏳ Waiting for other players...</span>
        )}
      </div>

      {invalidPlay && (
        <div className="invalid-warning">
          ⚠️ Invalid play: {invalidPlay}
        </div>
      )}

      <div className="button-group">
        <button
          className="action-button play-button"
          onClick={() => onPlay(selectedCards)}
          disabled={!canPlay}
          title={
            !isMyTurn
              ? 'Not your turn'
              : selectedCards.length === 0
              ? 'Select cards to play'
              : invalidPlay
              ? `Invalid: ${invalidPlay}`
              : 'Play selected cards'
          }
        >
          🎴 Play Cards
          {selectedCards.length > 0 && ` (${selectedCards.length})`}
        </button>

        <button
          className="action-button draw-button"
          onClick={onDraw}
          disabled={!canDraw}
          title={
            !isMyTurn
              ? 'Not your turn'
              : currentAction !== 'draw'
              ? 'Must play cards first'
              : 'Draw a card'
          }
        >
          📥 Draw Card
        </button>

        <button
          className={`action-button zapzap-button ${zapZapEligible ? 'highlight' : ''}`}
          onClick={onZapZap}
          disabled={!canZapZap}
          title={
            !isMyTurn
              ? 'Not your turn'
              : !zapZapEligible
              ? 'Hand value must be ≤5 points'
              : 'Call ZapZap to end the round!'
          }
        >
          ⚡ ZapZap!
        </button>
      </div>
    </div>
  );
}

export default ActionButtons;
