import { Play, Download, Zap, Sparkles, Clock } from 'lucide-react';

/**
 * ActionButtons component - Play, Draw, ZapZap actions
 * Responsive: compact layout on mobile
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
    <div className="bg-slate-800 rounded-lg shadow-xl p-2 sm:p-4 border border-slate-700">
      {/* Turn indicator - compact on mobile */}
      <div className="mb-2 sm:mb-4">
        {isMyTurn ? (
          <div className="flex items-center justify-center bg-green-900/30 border border-green-700 rounded-lg p-2 sm:p-3">
            <Sparkles className="w-4 h-4 sm:w-5 sm:h-5 text-green-400 mr-1 sm:mr-2" />
            <span className="text-green-400 font-semibold text-xs sm:text-base">
              <span className="sm:hidden">{currentAction === 'draw' ? 'Draw!' : 'Play!'}</span>
              <span className="hidden sm:inline">Your Turn - {currentAction === 'draw' ? 'Draw a card' : 'Play cards'}</span>
            </span>
          </div>
        ) : (
          <div className="flex items-center justify-center bg-slate-700 border border-slate-600 rounded-lg p-2 sm:p-3">
            <Clock className="w-4 h-4 sm:w-5 sm:h-5 text-gray-400 mr-1 sm:mr-2 animate-pulse" />
            <span className="text-gray-400 font-semibold text-xs sm:text-base">
              <span className="sm:hidden">Waiting...</span>
              <span className="hidden sm:inline">Waiting for other players...</span>
            </span>
          </div>
        )}
      </div>

      {/* Invalid play warning - compact on mobile */}
      {invalidPlay && (
        <div className="bg-red-900 border border-red-700 text-red-200 px-2 py-1.5 sm:px-4 sm:py-3 rounded-lg mb-2 sm:mb-4 flex items-center text-xs sm:text-base" role="alert">
          <span className="mr-1 sm:mr-2">⚠️</span>
          <span className="truncate">{invalidPlay}</span>
        </div>
      )}

      {/* Action buttons - tighter on mobile */}
      <div className="grid grid-cols-3 gap-2 sm:gap-4">
        {/* Play Cards button */}
        <button
          onClick={() => onPlay(selectedCards)}
          disabled={!canPlay}
          className={`flex flex-col sm:flex-row items-center justify-center px-2 py-2 sm:px-4 sm:py-3 font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-40 disabled:cursor-not-allowed text-xs sm:text-base ${
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
          <Play className="w-4 h-4 sm:w-5 sm:h-5 sm:mr-2" />
          <span className="hidden sm:inline">Play</span>
          {selectedCards.length > 0 && (
            <span className="sm:ml-1 bg-white/20 px-1.5 py-0.5 rounded-full text-[10px] sm:text-sm">
              {selectedCards.length}
            </span>
          )}
        </button>

        {/* Single Draw button - adapts based on discard selection */}
        <button
          onClick={handleDraw}
          disabled={!canDraw}
          className={`flex flex-col sm:flex-row items-center justify-center px-2 py-2 sm:px-4 sm:py-3 font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-40 disabled:cursor-not-allowed text-xs sm:text-base ${
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
          <Download className="w-4 h-4 sm:w-5 sm:h-5 sm:mr-2" />
          <span className="hidden sm:inline">{willDrawFromDiscard ? 'Take' : 'Draw'}</span>
        </button>

        {/* ZapZap button */}
        <button
          onClick={onZapZap}
          disabled={!canZapZap}
          className={`flex flex-col sm:flex-row items-center justify-center px-2 py-2 sm:px-4 sm:py-3 font-semibold rounded-lg transition-all shadow-lg disabled:opacity-40 disabled:cursor-not-allowed text-xs sm:text-base ${
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
          <Zap className="w-4 h-4 sm:w-5 sm:h-5 sm:mr-1" />
          <span className="text-[10px] sm:text-base">ZapZap!</span>
        </button>
      </div>
    </div>
  );
}

export default ActionButtons;
