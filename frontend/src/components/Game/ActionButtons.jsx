import { Play, Download, Zap, Sparkles, Clock } from 'lucide-react';

/**
 * ActionButtons component - Play, Draw, ZapZap actions
 * @param {number[]} selectedCards - Currently selected cards from hand
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
  // Play button logic - can only play during 'play' phase
  const canPlay = isMyTurn && currentAction === 'play' && selectedCards.length > 0 && !invalidPlay;

  // Draw button logic - can ONLY draw during 'draw' phase (after playing cards)
  // Single button: draws from discard if a card is selected, otherwise from deck
  const canDraw = isMyTurn && currentAction === 'draw';

  // ZapZap button logic - only allowed during 'play' phase
  const canZapZap = isMyTurn && zapZapEligible && currentAction === 'play';

  // Determine draw action and label
  const willDrawFromDiscard = hasDiscardSelection && hasDiscardCards;
  const handleDraw = willDrawFromDiscard ? onDrawFromDiscard : onDrawFromDeck;

  return (
    <div className="bg-slate-800 rounded-lg shadow-xl p-6 border border-slate-700">
      {/* Turn indicator */}
      <div className="mb-6">
        {isMyTurn ? (
          <div className="flex items-center justify-center bg-green-900/30 border border-green-700 rounded-lg p-4">
            <Sparkles className="w-5 h-5 text-green-400 mr-2" />
            <span className="text-green-400 font-semibold">
              Your Turn - {currentAction === 'draw' ? 'Draw a card' : 'Play cards'}
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
      <div className="grid grid-cols-3 gap-4">
        {/* Play Cards button */}
        <button
          onClick={() => onPlay(selectedCards)}
          disabled={!canPlay}
          className={`flex items-center justify-center px-4 py-4 font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-40 disabled:cursor-not-allowed ${
            currentAction === 'play'
              ? 'bg-amber-500 hover:bg-amber-600 text-white disabled:bg-slate-700'
              : 'bg-slate-700 text-white'
          }`}
          title={
            !isMyTurn
              ? 'Not your turn'
              : currentAction !== 'play'
              ? 'You must draw a card first'
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

        {/* Single Draw button - adapts based on discard selection */}
        <button
          onClick={handleDraw}
          disabled={!canDraw}
          className={`flex items-center justify-center px-4 py-4 font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-40 disabled:cursor-not-allowed ${
            currentAction === 'draw'
              ? willDrawFromDiscard
                ? 'bg-green-600 hover:bg-green-700 text-white'
                : 'bg-blue-600 hover:bg-blue-700 text-white'
              : 'bg-slate-700 text-white'
          }`}
          title={
            !isMyTurn
              ? 'Not your turn'
              : currentAction !== 'draw'
              ? 'You must play cards first'
              : willDrawFromDiscard
              ? 'Draw selected card from discard'
              : 'Draw from deck'
          }
        >
          <Download className="w-5 h-5 mr-2" />
          {willDrawFromDiscard ? 'Draw Selected' : 'Draw'}
        </button>

        {/* ZapZap button */}
        <button
          onClick={onZapZap}
          disabled={!canZapZap}
          className={`flex items-center justify-center px-4 py-4 font-semibold rounded-lg transition-all shadow-lg disabled:opacity-40 disabled:cursor-not-allowed ${
            canZapZap
              ? 'bg-amber-400 hover:bg-amber-500 text-slate-900 animate-pulse'
              : 'bg-slate-700 text-white'
          }`}
          title={
            !isMyTurn
              ? 'Not your turn'
              : currentAction !== 'play'
              ? 'ZapZap can only be called during play phase'
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
