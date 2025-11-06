import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { apiClient } from '../../services/api';
import { getCurrentUser } from '../../services/auth';

function PartyLobby() {
  const { partyId } = useParams();
  const [party, setParty] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const navigate = useNavigate();
  const currentUser = getCurrentUser();

  useEffect(() => {
    fetchPartyDetails();
    // TODO: Set up SSE for real-time updates
  }, [partyId]);

  const fetchPartyDetails = async () => {
    try {
      const response = await apiClient.get(`/party/${partyId}`);
      setParty(response.data.party);
      setError('');
    } catch (err) {
      setError('Failed to load party details');
    } finally {
      setLoading(false);
    }
  };

  const handleLeave = async () => {
    try {
      await apiClient.post(`/party/${partyId}/leave`);
      navigate('/parties');
    } catch (err) {
      setError('Failed to leave party');
    }
  };

  const handleStart = async () => {
    try {
      await apiClient.post(`/party/${partyId}/start`);
      navigate(`/game/${partyId}`);
    } catch (err) {
      setError('Failed to start game');
    }
  };

  if (loading) {
    return <div>Loading party...</div>;
  }

  if (!party) {
    return <div>Party not found</div>;
  }

  const isOwner = currentUser?.id === party.ownerId;
  const playerCount = party.players?.length || 0;
  const minPlayers = 3; // Game rule from README line 89

  return (
    <div className="party-lobby-container">
      <div className="party-lobby-card">
        <h1>{party.name}</h1>

        <div className="party-settings">
          <p>Max Players: {party.settings?.playerCount || 5} players</p>
          <p>Hand Size: {party.settings?.handSize || 7} cards</p>
          <p>Status: {party.status}</p>
        </div>

        <div className="players-section">
          <h2>Players ({playerCount}/{party.settings?.playerCount || 5})</h2>
          <div className="players-list">
            {party.players?.map((player, index) => (
              <div key={player.userId} className="player-item">
                <span>{player.username || `Player ${index + 1}`}</span>
                {player.userId === party.ownerId && <span className="owner-badge">Owner</span>}
              </div>
            ))}
          </div>
        </div>

        {error && <div className="error-message">{error}</div>}

        <div className="lobby-actions">
          {isOwner && (
            <button
              onClick={handleStart}
              disabled={playerCount < minPlayers}
              className="start-button"
              title={playerCount < minPlayers ? `Need at least ${minPlayers} players to start` : ''}
            >
              Start Game
              {playerCount < minPlayers && ` (${playerCount}/${minPlayers})`}
            </button>
          )}

          <button
            onClick={handleLeave}
            className="leave-button"
          >
            Leave Party
          </button>
        </div>
      </div>
    </div>
  );
}

export default PartyLobby;
