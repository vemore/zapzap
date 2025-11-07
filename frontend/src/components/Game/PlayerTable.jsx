import './PlayerTable.css';

/**
 * PlayerTable component - displays all players at the table
 * @param {Object[]} players - Array of player objects
 * @param {string} currentTurnId - ID of player whose turn it is
 * @param {string} currentUserId - ID of the current user
 */
function PlayerTable({ players = [], currentTurnId, currentUserId }) {
  if (players.length === 0) {
    return (
      <div className="player-table empty">
        <p>Waiting for players...</p>
      </div>
    );
  }

  return (
    <div className="player-table">
      <h3>Players</h3>
      <div className="players-grid">
        {players.map((player) => (
          <PlayerCard
            key={player.id}
            player={player}
            isCurrentUser={player.id === currentUserId}
            isCurrentTurn={player.id === currentTurnId}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * PlayerCard component - displays a single player
 */
function PlayerCard({ player, isCurrentUser, isCurrentTurn }) {
  const className = [
    'player-card',
    isCurrentUser && 'current-user',
    isCurrentTurn && 'current-turn',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={className}>
      <div className="player-header">
        <span className="player-name">
          {player.username}
          {isCurrentUser && <span className="you-badge"> (You)</span>}
        </span>
        {isCurrentTurn && <span className="turn-indicator">▶ Playing</span>}
      </div>

      <div className="player-stats">
        <div className="stat">
          <span className="stat-label">Cards:</span>
          <span className="stat-value">
            {player.cardCount} {player.cardCount === 1 ? 'card' : 'cards'}
          </span>
        </div>

        {player.score !== undefined && (
          <div className="stat">
            <span className="stat-label">Score:</span>
            <span className="stat-value">{player.score}</span>
          </div>
        )}
      </div>
    </div>
  );
}

export default PlayerTable;
