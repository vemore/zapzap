import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiClient } from '../../services/api';

function CreateParty() {
  const [name, setName] = useState('');
  const [playerCount, setPlayerCount] = useState(5);
  const [handSize, setHandSize] = useState(7);
  const [visibility, setVisibility] = useState('public');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();

    const numPlayers = parseInt(playerCount);
    const numHandSize = parseInt(handSize);

    // Game rule validation: 3-8 players (README line 89)
    if (numPlayers < 3 || numPlayers > 8) {
      setError('Player count must be between 3 and 8');
      setLoading(false);
      return;
    }

    // Game rule validation: 5-7 card hand size (README line 91)
    if (numHandSize < 5 || numHandSize > 7) {
      setError('Hand size must be between 5 and 7');
      setLoading(false);
      return;
    }

    if (!name.trim()) {
      setError('Party name is required');
      setLoading(false);
      return;
    }

    setError('');
    setLoading(true);

    try {
      const response = await apiClient.post('/party', {
        name: name.trim(),
        visibility,
        settings: {
          playerCount: parseInt(playerCount),
          handSize: parseInt(handSize),
        },
      });

      const partyId = response.data.party.id;
      navigate(`/party/${partyId}`);
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to create party');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="create-party-container">
      <div className="create-party-card">
        <h1>Create New Party</h1>

        <form onSubmit={handleSubmit} className="create-party-form">
          <div className="form-group">
            <label htmlFor="party-name">Party Name</label>
            <input
              id="party-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Enter party name"
              disabled={loading}
            />
          </div>

          <div className="form-group">
            <label htmlFor="player-count">Player Count (3-8)</label>
            <input
              id="player-count"
              type="number"
              min="3"
              max="8"
              value={playerCount}
              onChange={(e) => setPlayerCount(e.target.value)}
              disabled={loading}
            />
            <small>Minimum 3 players, maximum 8 players</small>
          </div>

          <div className="form-group">
            <label htmlFor="hand-size">Hand Size (5-7 cards)</label>
            <input
              id="hand-size"
              type="number"
              min="5"
              max="7"
              value={handSize}
              onChange={(e) => setHandSize(e.target.value)}
              disabled={loading}
            />
            <small>Starting hand size: 5-7 cards</small>
          </div>

          <div className="form-group">
            <label htmlFor="visibility">Visibility</label>
            <select
              id="visibility"
              value={visibility}
              onChange={(e) => setVisibility(e.target.value)}
              disabled={loading}
            >
              <option value="public">Public</option>
              <option value="private">Private</option>
            </select>
          </div>

          {error && (
            <div className="error-message" role="alert">
              {error}
            </div>
          )}

          <button
            type="submit"
            className="submit-button"
            disabled={loading}
          >
            {loading ? 'Creating...' : 'Create Party'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default CreateParty;
