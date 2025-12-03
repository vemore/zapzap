import { Play, Download, Zap, Sparkles, Clock, Layers } from 'lucide-react';

/**
 * ActionButtons component - Play, Draw, ZapZap actions
 * @param {number[]} selectedCards - Currently selected cards
 * @param {Function} onPlay - Play selected cards
 * @param {Function} onDrawFromDeck - Draw from deck
 * @param {Function} onDrawFromDiscard - Draw selected card from discard
 * @param {Function} onZapZap - Call ZapZap
 * @param {string} currentAction - Current required action ('play' or 'draw')
 * @param {boolean} isMyTurn - Is it the current player's turn
 * @param {boolean} zapZapEligible - Can call ZapZap
 * @param {string} invalidPlay - Invalid play reason
 * @param {boolean} hasDiscardSelection - A discard card is selected
 * @param {boolean} hasDiscardCards - There are cards in the discard pile
 */
function ActionButtons({
  selectedCards = [],
  onPlay,
  onDrawFromDeck,
  onDrawFromDiscard,
  onZapZap,
  currentAction = 'play',
  isMyTurn = false,
  zapZapEligible = false,
  invalidPlay = null,
  hasDiscardSelection = false,
  hasDiscardCards = false,
}) {
  // Play button logic
  const canPlay = isMyTurn && selectedCards.length > 0 && !invalidPlay;

  // Draw button logic
  const canDrawFromDeck = isMyTurn && currentAction === 'draw';
  const canDrawFromDiscard = isMyTurn && currentAction === 'draw' && hasDiscardCards && hasDiscardSelection;

  // ZapZap button logic
  const canZapZap = isMyTurn && zapZapEligible;

  return (
    <div className="bg-slate-800 rounded-lg shadow-xl p-6 border border-slate-700">
      {/* Turn indicator */}
      <div className="mb-6">
        {isMyTurn ? (
          <div className="flex items-center justify-center bg-green-900/30 border border-green-700 rounded-lg p-4">
            <Sparkles className="w-5 h-5 text-green-400 mr-2" />
            <span className="text-green-400 font-semibold">
              Your Turn - {currentAction === 'draw' ? 'Draw a card' : 'Play cards or Draw'}
            </span>
          </div>
        ) : (
          <div className="flex items-center justify-center bg-slate-700 border border-slate-600 rounded-lg p-4">
            <Clock className="w-5 h-5 text-gray-400 mr-2 animate-pulse" />
            <span className="text-gray-400 font-semibold">Waiting for other players...</span>
          </div>
        )}
      </div>

      {/* Invalid play warning */}
      {invalidPlay && (
        <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg mb-6 flex items-center" role="alert">
          <span className="mr-2">⚠️</span>
          <span>Invalid play: {invalidPlay}</span>
        </div>
      )}

      {/* Action buttons */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {/* Play Cards button */}
        <button
          onClick={() => onPlay(selectedCards)}
          disabled={!canPlay}
          className="flex items-center justify-center px-4 py-4 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-40 disabled:cursor-not-allowed disabled:bg-slate-700"
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
          <Play className="w-5 h-5 mr-2" />
          Play Cards
          {selectedCards.length > 0 && (
            <span className="ml-2 bg-white/20 px-2 py-0.5 rounded-full text-sm">
              {selectedCards.length}
            </span>
          )}
        </button>

        {/* Draw from Deck button */}
        <button
          onClick={onDrawFromDeck}
          disabled={!canDrawFromDeck}
          className="flex items-center justify-center px-4 py-4 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          title={
            !isMyTurn
              ? 'Not your turn'
              : currentAction !== 'draw'
              ? 'Must play cards first'
              : 'Draw from deck'
          }
        >
          <Download className="w-5 h-5 mr-2" />
          Draw Deck
        </button>

        {/* Draw from Discard button */}
        <button
          onClick={onDrawFromDiscard}
          disabled={!canDrawFromDiscard}
          className={`flex items-center justify-center px-4 py-4 font-semibold rounded-lg transition-colors disabled:opacity-40 disabled:cursor-not-allowed ${
            hasDiscardSelection
              ? 'bg-green-600 hover:bg-green-700 text-white'
              : 'bg-slate-700 text-white'
          }`}
          title={
            !isMyTurn
              ? 'Not your turn'
              : currentAction !== 'draw'
              ? 'Must play cards first'
              : !hasDiscardCards
              ? 'No cards in discard pile'
              : !hasDiscardSelection
              ? 'Select a card from the discard pile first'
              : 'Draw selected card'
          }
        >
          <Layers className="w-5 h-5 mr-2" />
          {hasDiscardSelection ? 'Draw Selected' : 'Draw Discard'}
        </button>

        {/* ZapZap button */}
        <button
          onClick={onZapZap}
          disabled={!canZapZap}
          className={`flex items-center justify-center px-4 py-4 font-semibold rounded-lg transition-all shadow-lg disabled:opacity-40 disabled:cursor-not-allowed ${
            zapZapEligible
              ? 'bg-amber-400 hover:bg-amber-500 text-slate-900 animate-pulse'
              : 'bg-slate-700 text-white'
          }`}
          title={
            !isMyTurn
              ? 'Not your turn'
              : !zapZapEligible
              ? 'Hand value must be ≤5 points'
              : 'Call ZapZap to end the round!'
          }
        >
          <Zap className="w-5 h-5 mr-2" />
          ZapZap!
        </button>
      </div>
    </div>
  );
}

export default ActionButtons;
