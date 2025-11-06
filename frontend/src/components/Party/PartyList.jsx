import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { apiClient } from '../../services/api';

function PartyList() {
  const [parties, setParties] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const navigate = useNavigate();

  useEffect(() => {
    fetchParties();
  }, []);

  const fetchParties = async () => {
    try {
      const response = await apiClient.get('/party');
      setParties(response.data.parties || []);
      setError('');
    } catch (err) {
      setError('Failed to fetch parties');
    } finally {
      setLoading(false);
    }
  };

  const handleJoin = async (partyId) => {
    try {
      await apiClient.post(`/party/${partyId}/join`);
      navigate(`/party/${partyId}`);
    } catch (err) {
      setError('Failed to join party');
    }
  };

  if (loading) {
    return <div>Loading parties...</div>;
  }

  return (
    <div className="party-list-container">
      <div className="party-list-header">
        <h1>Available Parties</h1>
        <Link to="/create-party">
          <button className="create-party-btn">Create Party</button>
        </Link>
      </div>

      {error && <div className="error-message">{error}</div>}

      {parties.length === 0 ? (
        <div className="empty-state">No parties available. Create one to get started!</div>
      ) : (
        <div className="parties-grid">
          {parties.map((party) => (
            <div key={party.id} className="party-card">
              <h3>{party.name}</h3>
              <div className="party-info">
                <p>Players: {party.playerCount || 0}/{party.maxPlayers || party.settings?.playerCount || 5}</p>
                <p>Status: {party.status}</p>
              </div>
              <button
                onClick={() => handleJoin(party.id)}
                disabled={
                  party.playerCount >= (party.maxPlayers || party.settings?.playerCount || 5) ||
                  party.status === 'playing'
                }
                className="join-btn"
              >
                {party.status === 'playing' ? 'In Progress' : party.playerCount >= (party.maxPlayers || 5) ? 'Full' : 'Join'}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default PartyList;
