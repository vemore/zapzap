import { useState } from 'react';
import { Dice6, Loader } from 'lucide-react';
import PlayerTable from './PlayerTable';
import PlayerHand from './PlayerHand';
import ActionButtons from './ActionButtons';
import { isValidPlay, analyzePlay } from '../../utils/validation';
import { isZapZapEligible } from '../../utils/scoring';

/**
 * GameBoard component - main game interface
 * @param {Object} gameState - Complete game state
 * @param {Function} onPlay - Play selected cards
 * @param {Function} onDraw - Draw a card
 * @param {Function} onZapZap - Call ZapZap
 */
function GameBoard({ gameState, onPlay, onDraw, onZapZap }) {
  const [selectedCards, setSelectedCards] = useState([]);

  if (!gameState) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="flex items-center text-white">
          <Loader className="w-8 h-8 mr-3 animate-spin text-amber-400" />
          <span className="text-xl">Loading game...</span>
        </div>
      </div>
    );
  }

  const {
    partyId,
    players = [],
    currentTurnId,
    currentAction = 'play',
    myHand = [],
    myUserId,
  } = gameState;

  const isMyTurn = currentTurnId === myUserId;
  const zapZapEligible = isZapZapEligible(myHand);

  // Validate selected cards
  let invalidPlay = null;
  if (selectedCards.length > 0) {
    const analysis = analyzePlay(selectedCards);
    if (!analysis.valid) {
      invalidPlay = analysis.reason;
    }
  }

  // Action handlers
  const handlePlay = (cards) => {
    if (isValidPlay(cards)) {
      onPlay(cards);
      setSelectedCards([]);
    }
  };

  const handleDraw = () => {
    onDraw();
    setSelectedCards([]);
  };

  const handleZapZap = () => {
    onZapZap();
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            {/* Logo */}
            <div className="flex items-center">
              <Dice6 className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">ZapZap Game</h1>
            </div>

            {/* Party info */}
            <div className="flex items-center">
              <span className="text-gray-300">
                Party: <span className="font-semibold text-white">{partyId}</span>
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Main game layout */}
      <div className="max-w-7xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
          {/* Players sidebar */}
          <aside className="lg:col-span-1">
            <PlayerTable
              players={players}
              currentTurnId={currentTurnId}
              currentUserId={myUserId}
            />
          </aside>

          {/* Play area */}
          <main className="lg:col-span-3 space-y-6">
            {/* My hand section */}
            <section>
              <PlayerHand
                hand={myHand}
                onCardsSelected={setSelectedCards}
                disabled={!isMyTurn}
              />
            </section>

            {/* Action buttons section */}
            <section>
              <ActionButtons
                selectedCards={selectedCards}
                onPlay={handlePlay}
                onDraw={handleDraw}
                onZapZap={handleZapZap}
                currentAction={currentAction}
                isMyTurn={isMyTurn}
                zapZapEligible={zapZapEligible}
                invalidPlay={invalidPlay}
              />
            </section>
          </main>
        </div>
      </div>
    </div>
  );
}

export default GameBoard;
