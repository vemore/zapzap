import { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { ArrowLeft, Zap, Bot, User } from 'lucide-react';
import { apiClient } from '../../services/api';

function CreateParty() {
  const [name, setName] = useState('');
  const [playerCount, setPlayerCount] = useState(5);
  const [visibility, setVisibility] = useState('public');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [availableBots, setAvailableBots] = useState([]);
  const [playerSlots, setPlayerSlots] = useState([]);
  const navigate = useNavigate();

  // Fetch available bots on component mount
  useEffect(() => {
    const fetchBots = async () => {
      try {
        const response = await apiClient.get('/bots');
        setAvailableBots(response.data.bots || []);
      } catch (err) {
        console.error('Failed to fetch bots:', err);
        // Don't show error to user, just won't have bot options
      }
    };

    fetchBots();
  }, []);

  // Initialize player slots when player count changes
  useEffect(() => {
    const count = parseInt(playerCount);
    if (count >= 3 && count <= 8) {
      // Slot 0 is owner (always human), slots 1+ are configurable
      const slots = Array.from({ length: count - 1 }, (_, i) => ({
        index: i + 1,
        type: 'human', // 'human' or 'bot'
        botId: null,
        difficulty: null
      }));
      setPlayerSlots(slots);
    }
  }, [playerCount]);

  // Handle player slot configuration change
  const handleSlotChange = (slotIndex, type, difficulty = null) => {
    setPlayerSlots(prevSlots => {
      const newSlots = [...prevSlots];
      const slot = newSlots[slotIndex];

      if (type === 'human') {
        slot.type = 'human';
        slot.botId = null;
        slot.difficulty = null;
      } else if (type === 'bot' && difficulty) {
        slot.type = 'bot';
        slot.difficulty = difficulty;
        // Find first available bot of this difficulty that isn't already used
        const usedBotIds = new Set(newSlots.filter((s, i) => i !== slotIndex && s.type === 'bot').map(s => s.botId));
        const botsOfDifficulty = availableBots.filter(b => b.botDifficulty === difficulty && !usedBotIds.has(b.id));
        if (botsOfDifficulty.length > 0) {
          slot.botId = botsOfDifficulty[0].id;
        } else {
          // No available bot of this difficulty, fallback to human
          slot.type = 'human';
          slot.botId = null;
          slot.difficulty = null;
        }
      }

      return newSlots;
    });
  };

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
      // Extract bot IDs from player slots
      const botIds = playerSlots
        .filter(slot => slot.type === 'bot' && slot.botId)
        .map(slot => slot.botId);

      const response = await apiClient.post('/party', {
        name: name.trim(),
        visibility,
        settings: {
          playerCount: parseInt(playerCount),
        },
        botIds
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

            {/* Player Slots Configuration */}
            {playerSlots.length > 0 && (
              <div className="bg-slate-700/50 rounded-lg p-4 border border-slate-600">
                <label className="block text-sm font-medium text-gray-300 mb-3">
                  Configure Player Slots
                </label>

                {/* Owner slot (always human) */}
                <div className="mb-3 p-3 bg-slate-800 rounded-lg border border-amber-400/30">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center">
                      <User className="w-4 h-4 text-amber-400 mr-2" />
                      <span className="text-white font-medium">Player 1 (You)</span>
                    </div>
                    <span className="text-xs text-gray-400 bg-amber-400/20 px-2 py-1 rounded">Owner</span>
                  </div>
                </div>

                {/* Configurable slots */}
                <div className="space-y-2">
                  {playerSlots.map((slot, index) => {
                    // Calculate available bots per difficulty, excluding bots already used in other slots
                    const usedBotIds = new Set(
                      playerSlots
                        .filter((s, i) => i !== index && s.type === 'bot')
                        .map(s => s.botId)
                    );

                    const getAvailableCount = (difficulty) => {
                      return availableBots.filter(b =>
                        b.botDifficulty === difficulty && !usedBotIds.has(b.id)
                      ).length;
                    };

                    // For current slot, if it's using a bot of a certain difficulty, that bot is still "available" for this slot
                    const getAvailableCountForSlot = (difficulty) => {
                      const baseCount = getAvailableCount(difficulty);
                      // If this slot is already using a bot of this difficulty, it's available for this slot
                      if (slot.type === 'bot' && slot.difficulty === difficulty) {
                        return baseCount + 1;
                      }
                      return baseCount;
                    };

                    const easyCount = getAvailableCountForSlot('easy');
                    const mediumCount = getAvailableCountForSlot('medium');
                    const hardCount = getAvailableCountForSlot('hard');
                    const hardVinceCount = getAvailableCountForSlot('hard_vince');
                    const llmCount = getAvailableCountForSlot('llm');
                    const thibotCount = getAvailableCountForSlot('thibot');

                    return (
                      <div key={slot.index} className="p-3 bg-slate-800 rounded-lg border border-slate-600">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center">
                            {slot.type === 'bot' ? (
                              <Bot className="w-4 h-4 text-purple-400 mr-2" />
                            ) : (
                              <User className="w-4 h-4 text-gray-400 mr-2" />
                            )}
                            <span className="text-white text-sm">Player {slot.index + 1}</span>
                          </div>
                          <select
                            value={slot.type === 'bot' ? `bot-${slot.difficulty}` : 'human'}
                            onChange={(e) => {
                              const value = e.target.value;
                              if (value === 'human') {
                                handleSlotChange(index, 'human');
                              } else {
                                const difficulty = value.replace('bot-', '');
                                handleSlotChange(index, 'bot', difficulty);
                              }
                            }}
                            disabled={loading}
                            className="px-3 py-1 text-sm bg-slate-700 border border-slate-600 rounded text-white focus:outline-none focus:border-amber-400 transition-colors disabled:opacity-60"
                          >
                            <option value="human">Waiting for Human</option>
                            <option value="bot-easy" disabled={easyCount === 0}>
                              Bot - Easy {easyCount === 0 && '(None available)'}
                            </option>
                            <option value="bot-medium" disabled={mediumCount === 0}>
                              Bot - Medium {mediumCount === 0 && '(None available)'}
                            </option>
                            <option value="bot-hard" disabled={hardCount === 0}>
                              Bot - Hard {hardCount === 0 && '(None available)'}
                            </option>
                            <option value="bot-hard_vince" disabled={hardVinceCount === 0}>
                              Bot - Hard Vince {hardVinceCount === 0 && '(None available)'}
                            </option>
                            <option value="bot-llm" disabled={llmCount === 0}>
                              Bot - LLM (Llama 3.3) {llmCount === 0 && '(None available)'}
                            </option>
                            <option value="bot-thibot" disabled={thibotCount === 0}>
                              Bot - Thibot {thibotCount === 0 && '(None available)'}
                            </option>
                          </select>
                        </div>
                      </div>
                    );
                  })}
                </div>

                {/* Summary */}
                <div className="mt-3 pt-3 border-t border-slate-600">
                  <div className="flex justify-between text-xs text-gray-400">
                    <span>Humans: {playerSlots.filter(s => s.type === 'human').length + 1}</span>
                    <span>Bots: {playerSlots.filter(s => s.type === 'bot').length}</span>
                  </div>
                </div>
              </div>
            )}

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
