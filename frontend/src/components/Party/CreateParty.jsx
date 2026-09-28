import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { ArrowLeft, Zap, Bot } from 'lucide-react';
import { apiClient } from '../../services/api';

// The form asks for the number of seats only: the creator takes the first, and the
// others wait in the lobby for players, or for bots the host adds there.

function CreateParty() {
  const [name, setName] = useState('');
  const [playerCount, setPlayerCount] = useState(5);
  const [visibility, setVisibility] = useState('public');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();

    const numPlayers = parseInt(playerCount);

    // Game rule validation: 3-8 players
    if (numPlayers < 3 || numPlayers > 8) {
      setError('Player count must be between 3 and 8');
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
        },
      });

      const partyId = response.data.party.id;
      navigate(`/party/${partyId}`);
    } catch (err) {
      setError(err.response?.data?.error || err.response?.data?.details || 'Failed to create party');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Back to parties link */}
        <Link
          to="/parties"
          className="inline-flex items-center text-gray-300 hover:text-white mb-6 transition-colors"
        >
          <ArrowLeft className="w-4 h-4 mr-2" />
          Back to Parties
        </Link>

        {/* Card */}
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700">
          {/* Header with logo */}
          <div className="flex items-center justify-center mb-6">
            <Zap className="w-8 h-8 text-amber-400 mr-3" />
            <h1 className="text-3xl font-bold text-white">Create New Party</h1>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Party Name */}
            <div>
              <label htmlFor="party-name" className="block text-sm font-medium text-gray-300 mb-2">
                Party Name
              </label>
              <input
                id="party-name"
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Enter party name"
                disabled={loading}
                className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:border-amber-400 transition-colors disabled:opacity-60"
              />
            </div>

            {/* Player Count */}
            <div>
              <label htmlFor="player-count" className="block text-sm font-medium text-gray-300 mb-2">
                Player Count (3-8)
              </label>
              <input
                id="player-count"
                type="number"
                min="3"
                max="8"
                value={playerCount}
                onChange={(e) => setPlayerCount(e.target.value)}
                disabled={loading}
                className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:border-amber-400 transition-colors disabled:opacity-60"
              />
              <p className="mt-1 text-xs text-gray-400">Minimum 3 players, maximum 8 players</p>
            </div>

            {/* Visibility */}
            <div>
              <label htmlFor="visibility" className="block text-sm font-medium text-gray-300 mb-2">
                Visibility
              </label>
              <select
                id="visibility"
                value={visibility}
                onChange={(e) => setVisibility(e.target.value)}
                disabled={loading}
                className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:border-amber-400 transition-colors disabled:opacity-60"
              >
                <option value="public">Public - Anyone can join</option>
                <option value="private">Private - Invite code required</option>
              </select>
            </div>

            {/* The free seats are filled in the lobby */}
            <p className="flex items-start text-sm text-gray-400" data-testid="seats-hint">
              <Bot className="w-4 h-4 mr-2 mt-0.5 flex-shrink-0 text-amber-400" />
              Once the party is created, you can add bots to the free seats in the lobby, or wait for other players.
            </p>

            {/* Error Message */}
            {error && (
              <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg" role="alert">
                {error}
              </div>
            )}

            {/* Submit Button */}
            <button
              type="submit"
              disabled={loading}
              className="w-full bg-amber-500 hover:bg-amber-600 text-white font-semibold py-3 rounded-lg transition-colors shadow-lg disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {loading ? 'Creating...' : 'Create Party'}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

export default CreateParty;
