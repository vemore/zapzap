import { getCardName } from '../../utils/cards';
import './RoundEnd.css';

/**
 * RoundEnd component - displays scoring at end of round
 * @param {Object} roundData - Round results
 * @param {Function} onContinue - Continue to next round
 * @param {boolean} disabled - Disable continue button
 */
function RoundEnd({ roundData, onContinue, disabled = false }) {
  if (!roundData) {
    return (
      <div className="round-end loading">
        <p>Calculating scores...</p>
      </div>
    );
  }

  const { players = [], zapZapCaller, roundNumber } = roundData;

  if (players.length === 0) {
    return (
      <div className="round-end error">
        <p>No players found</p>
      </div>
    );
  }

  // Find lowest hand value for this round
  const lowestScore = Math.min(...players.map((p) => p.score));
  const lowestPlayer = players.find((p) => p.score === lowestScore);

  // Check if ZapZap was called
  const zapZapPlayer = zapZapCaller ? players.find((p) => p.id === zapZapCaller) : null;
  const wasCounterActed = zapZapPlayer && zapZapPlayer.score > zapZapPlayer.handValue;

  // Sort players by score (lowest first)
  const sortedPlayers = [...players].sort((a, b) => a.score - b.score);

  // Check for eliminated players
  const eliminatedPlayers = players.filter((p) => p.totalScore > 100);

  return (
    <div className="round-end">
      <div className="round-end-header">
        <h2>Round {roundNumber} Complete!</h2>
        {zapZapPlayer && (
          <div className={`zapzap-indicator ${wasCounterActed ? 'counteracted' : 'successful'}`}>
            {wasCounterActed ? (
              <>
                <span className="icon">⚠️</span>
                <strong>{zapZapPlayer.username}</strong> called ZapZap but was{' '}
                <strong>Counteracted!</strong>
                <div className="penalty-info">
                  Penalty: {zapZapPlayer.handValue} + ({players.length} × 5) = {zapZapPlayer.score} points
                </div>
              </>
            ) : (
              <>
                <span className="icon">✨</span>
                <strong>{zapZapPlayer.username}</strong> successfully called <strong>ZapZap!</strong>
              </>
            )}
          </div>
        )}
      </div>

      <div className="players-results">
        {sortedPlayers.map((player) => {
          const isLowest = player.id === lowestPlayer?.id;
          const isEliminated = player.totalScore > 100;
          const isZapZapCaller = player.id === zapZapCaller;

          return (
            <div
              key={player.id}
              className={`player-row ${isLowest ? 'lowest' : ''} ${
                isEliminated ? 'eliminated' : ''
              }`}
            >
              <div className="player-info">
                <div className="player-name">
                  {player.username}
                  {isLowest && <span className="badge winner">Lowest Hand</span>}
                  {isEliminated && <span className="badge eliminated-badge">Eliminated</span>}
                  {isZapZapCaller && <span className="badge zapzap">ZapZap</span>}
                </div>
              </div>

              <div className="player-hand-display">
                {player.hand.map((cardId, idx) => (
                  <span key={`${cardId}-${idx}`} className="card-name">
                    {getCardName(cardId)}
                  </span>
                ))}
              </div>

              <div className="scores">
                <div className="round-score">
                  <span className="label">This Round:</span>
                  <span className="value">{player.score} points</span>
                </div>
                <div className="total-score">
                  <span className="label">Total:</span>
                  <span className="value">{player.totalScore}</span>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {eliminatedPlayers.length > 0 && (
        <div className="eliminations">
          <h3>Eliminated Players</h3>
          {eliminatedPlayers.map((player) => (
            <p key={player.id}>
              <strong>{player.username}</strong> eliminated with {player.totalScore} points
            </p>
          ))}
        </div>
      )}

      <div className="actions">
        <button
          onClick={onContinue}
          disabled={disabled}
          className="continue-button"
        >
          Continue to Next Round
        </button>
      </div>
    </div>
  );
}

export default RoundEnd;
