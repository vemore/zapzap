import { useState } from 'react';
import PlayerTable from './PlayerTable';
import PlayerHand from './PlayerHand';
import ActionButtons from './ActionButtons';
import { isValidPlay, analyzePlay } from '../../utils/validation';
import { isZapZapEligible } from '../../utils/scoring';
import './GameBoard.css';

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
      <div className="game-board loading">
        <p>Loading game...</p>
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
    <div className="game-board">
      <div className="game-header">
        <h2>ZapZap Game</h2>
        <span className="party-id">Party: {partyId}</span>
      </div>

      <div className="game-layout">
        <aside className="players-section">
          <PlayerTable
            players={players}
            currentTurnId={currentTurnId}
            currentUserId={myUserId}
          />
        </aside>

        <main className="play-area">
          <section className="my-hand-section">
            <PlayerHand
              hand={myHand}
              onCardsSelected={setSelectedCards}
              disabled={!isMyTurn}
            />
          </section>

          <section className="actions-section">
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
  );
}

export default GameBoard;
