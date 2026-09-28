import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Zap, LogOut, Play, ArrowLeft, Users, Loader, Crown, Settings, Bot, Trash2, Wifi, WifiOff } from 'lucide-react';
import { apiClient } from '../../services/api';
import {
  BOT_DIFFICULTIES,
  FILL_DIFFICULTIES,
  addBotToParty,
  fillAndStart,
  listBots,
} from '../../services/party';
import { useAuth } from '../../contexts/AuthContext';
import useSSE from '../../hooks/useSSE';
import { sseUrl } from '../../services/sse';

function PartyLobby() {
  const { partyId } = useParams();
  const [party, setParty] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [bots, setBots] = useState([]);
  const [busy, setBusy] = useState(false);
  // The fill-with-bots dialog: closed, or open on the level it will seat
  const [fillOpen, setFillOpen] = useState(false);
  const [fillLevel, setFillLevel] = useState('medium');
  const navigate = useNavigate();
  const { user, logout } = useAuth();

  // Handle SSE messages for real-time updates
  const handleSSEMessage = useCallback((data) => {
    // Only process events for this party
    if (data.partyId !== partyId) return;

    switch (data.action) {
      case 'playerJoined':
      case 'playerLeft':
        // Refresh party details when players join or leave
        fetchPartyDetails();
        break;
      case 'partyStarted':
        // Navigate to game when party starts
        navigate(`/game/${partyId}`);
        break;
      case 'partyDeleted':
        // Navigate back to parties list if party is deleted
        navigate('/parties');
        break;
      default:
        break;
    }
  }, [partyId, navigate]);

  // Set up SSE connection for real-time updates (the stream carries the user's token)
  const { connected: sseConnected } = useSSE(sseUrl(), {
    onMessage: handleSSEMessage
  });

  useEffect(() => {
    fetchPartyDetails();
  }, [partyId]);

  // The bot accounts a free seat can take
  useEffect(() => {
    listBots().then(setBots);
  }, []);

  const fetchPartyDetails = async () => {
    try {
      // Use cache-busting to ensure fresh data on SSE updates
      const response = await apiClient.get(`/party/${partyId}`, {
        headers: { 'Cache-Control': 'no-cache' },
        params: { _t: Date.now() }
      });
      // Merge party data with players array
      setParty({ ...response.data.party, players: response.data.players || [] });
      setError('');
    } catch {
      setError('Failed to load party details');
    } finally {
      setLoading(false);
    }
  };

  const handleLeave = async () => {
    try {
      await apiClient.post(`/party/${partyId}/leave`);
      navigate('/parties');
    } catch {
      setError('Failed to leave party');
    }
  };

  const handleDelete = async () => {
    if (!window.confirm('Are you sure you want to delete this party? This action cannot be undone.')) {
      return;
    }
    try {
      await apiClient.delete(`/party/${partyId}`);
      navigate('/parties');
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to delete party');
    }
  };

  const handleStart = async () => {
    try {
      await apiClient.post(`/party/${partyId}/start`);
      navigate(`/game/${partyId}`);
    } catch {
      setError('Failed to start game');
    }
  };

  // The owner seats the first bot of `difficulty` not at the table yet. Only on
  // request: nothing is filled or started by itself.
  const handleAddBot = async (difficulty) => {
    const seated = new Set((party?.players || []).map(p => p.userId));
    const bot = bots.find(b => b.botDifficulty === difficulty && !seated.has(b.id));
    if (!bot) return;
    setBusy(true);
    try {
      await addBotToParty(partyId, bot.id);
      await fetchPartyDetails();
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to add a bot');
    } finally {
      setBusy(false);
    }
  };

  const handleFillAndStart = async () => {
    setBusy(true);
    try {
      await fillAndStart(partyId, fillLevel);
      setFillOpen(false);
      navigate(`/game/${partyId}`);
    } catch (err) {
      setFillOpen(false);
      setError(
        err.response?.data?.code === 'NOT_ENOUGH_BOTS'
          ? 'Not enough bots available to fill the table.'
          : err.response?.data?.error || 'Failed to fill the party and start'
      );
    } finally {
      setBusy(false);
    }
  };

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="flex items-center text-white">
          <Loader className="w-8 h-8 mr-3 animate-spin text-amber-400" />
          <span className="text-xl">Loading party...</span>
        </div>
      </div>
    );
  }

  if (!party) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700 text-center">
          <Users className="w-16 h-16 text-gray-500 mx-auto mb-4" />
          <h2 className="text-2xl font-bold text-white mb-4">Party Not Found</h2>
          <p className="text-gray-400 mb-6">The party you're looking for doesn't exist.</p>
          <button
            onClick={() => navigate('/parties')}
            className="inline-flex items-center px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors"
          >
            <ArrowLeft className="w-4 h-4 mr-2" />
            Back to Parties
          </button>
        </div>
      </div>
    );
  }

  const isOwner = user?.id === party.ownerId;
  const playerCount = party.players?.length || 0;
  const minPlayers = 3; // Game rule from README line 89
  const maxPlayers = party.settings?.playerCount || 5;

  // Check if user is the only human player (all others are bots)
  const humanPlayers = party.players?.filter(p => p.userType !== 'bot') || [];
  const isOnlyHuman = humanPlayers.length === 1 && humanPlayers[0]?.userId === user?.id;

  // User can delete if they are owner OR the only human player
  const canDelete = isOwner || isOnlyHuman;

  // The owner seats bots in a waiting party with a free seat
  const freeSeats = Math.max(0, maxPlayers - playerCount);
  const canAddBots = isOwner && party.status === 'waiting' && freeSeats > 0;
  const seatedIds = new Set((party.players || []).map(p => p.userId));
  const availableBots = (difficulty) =>
    bots.filter(b => b.botDifficulty === difficulty && !seatedIds.has(b.id)).length;

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            {/* Logo */}
            <div className="flex items-center">
              <Zap className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">ZapZap</h1>
            </div>

            {/* User info and logout */}
            <div className="flex items-center space-x-4">
              {/* SSE connection indicator */}
              <div className="flex items-center" title={sseConnected ? 'Real-time updates active' : 'Connecting...'}>
                {sseConnected ? (
                  <Wifi className="w-4 h-4 text-green-400" />
                ) : (
                  <WifiOff className="w-4 h-4 text-gray-500 animate-pulse" />
                )}
              </div>
              <span className="text-gray-300">
                Welcome, <span className="font-semibold text-white">{user?.username}</span>
              </span>
              <button
                onClick={handleLogout}
                className="flex items-center px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition-colors"
              >
                <LogOut className="w-4 h-4 mr-2" />
                Logout
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        {/* Back to parties link */}
        <button
          onClick={() => navigate('/parties')}
          className="inline-flex items-center text-gray-300 hover:text-white mb-6 transition-colors"
        >
          <ArrowLeft className="w-4 h-4 mr-2" />
          Back to Parties
        </button>

        {/* Party card */}
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700 mb-6">
          {/* Party header */}
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-3xl font-bold text-white">{party.name}</h2>
            {isOwner && (
              <span className="inline-flex items-center px-3 py-1 bg-amber-400/20 text-amber-400 border border-amber-400/30 rounded-full text-sm font-semibold">
                <Crown className="w-4 h-4 mr-1" />
                Owner
              </span>
            )}
          </div>

          {/* Party settings */}
          <div className="bg-slate-700 rounded-lg p-4 mb-6">
            <div className="flex items-center mb-3">
              <Settings className="w-5 h-5 text-amber-400 mr-2" />
              <h3 className="text-lg font-semibold text-white">Game Settings</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Max Players:</span>
                <span className="text-white font-medium">{maxPlayers} players</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Hand Size:</span>
                <span className="text-white font-medium">{party.settings?.handSize || 7} cards</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Status:</span>
                <span className={`font-medium ${
                  party.status === 'playing' ? 'text-amber-400' : 'text-green-400'
                }`}>
                  {party.status === 'playing' ? 'Playing' : 'Waiting'}
                </span>
              </div>
            </div>
          </div>

          {/* Players section */}
          <div className="mb-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-xl font-semibold text-white flex items-center">
                <Users className="w-5 h-5 mr-2 text-amber-400" />
                Players ({playerCount}/{maxPlayers})
              </h3>
              {playerCount < minPlayers && (
                <span className="text-amber-400 text-sm">
                  Need {minPlayers - playerCount} more player{minPlayers - playerCount > 1 ? 's' : ''} to start
                </span>
              )}
            </div>

            {/* Players grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {party.players?.map((player) => (
                <div
                  key={player.userId}
                  className="bg-slate-700 rounded-lg p-4 border border-slate-600 hover:border-amber-400/50 transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-white font-medium">{player.username || 'Unknown'}</span>
                      {player.userType === 'bot' && (
                        <span className="flex items-center text-xs bg-purple-500/20 text-purple-400 border border-purple-500/30 px-2 py-0.5 rounded-full">
                          <Bot className="w-3 h-3 mr-1" />
                          {player.botDifficulty ? player.botDifficulty.charAt(0).toUpperCase() + player.botDifficulty.slice(1) : 'Bot'}
                        </span>
                      )}
                    </div>
                    {player.userId === party.ownerId && (
                      <Crown className="w-4 h-4 text-amber-400" />
                    )}
                  </div>
                </div>
              ))}

              {/* Empty player slots */}
              {Array.from({ length: freeSeats }).map((_, index) => (
                <div
                  key={`empty-${index}`}
                  data-testid={`empty-seat-${index}`}
                  className="bg-slate-700/30 rounded-lg p-4 border border-slate-600 border-dashed flex items-center justify-between gap-2"
                >
                  <span className="text-gray-500 font-medium whitespace-nowrap">Waiting for player...</span>
                  {canAddBots && (
                    <select
                      aria-label={`Add a bot to free seat ${index + 1}`}
                      value=""
                      disabled={busy}
                      onChange={(e) => e.target.value && handleAddBot(e.target.value)}
                      className="min-w-0 px-2 py-1 text-sm bg-slate-700 border border-slate-600 rounded text-amber-400 focus:outline-none focus:border-amber-400 disabled:opacity-60"
                    >
                      <option value="">Add a bot…</option>
                      {BOT_DIFFICULTIES.map(({ value, label }) => (
                        <option key={value} value={value} disabled={availableBots(value) === 0}>
                          {label}{availableBots(value) === 0 ? ' (none available)' : ''}
                        </option>
                      ))}
                    </select>
                  )}
                </div>
              ))}
            </div>

            {canAddBots && (
              <button
                onClick={() => setFillOpen(true)}
                disabled={busy}
                className="mt-4 w-full flex items-center justify-center px-6 py-3 bg-slate-700 hover:bg-slate-600 border border-amber-400/40 text-amber-400 font-semibold rounded-lg transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
              >
                <Bot className="w-5 h-5 mr-2" />
                Fill with bots and start
              </button>
            )}
          </div>

          {/* Error message */}
          {error && (
            <div className="bg-red-900 border border-red-700 text-red-200 px-4 py-3 rounded-lg mb-6" role="alert">
              {error}
            </div>
          )}

          {/* Action buttons */}
          <div className="flex flex-col sm:flex-row gap-4">
            {isOwner && (
              <button
                onClick={handleStart}
                disabled={playerCount < minPlayers}
                className="flex-1 flex items-center justify-center px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors shadow-lg disabled:opacity-60 disabled:cursor-not-allowed"
                title={playerCount < minPlayers ? `Need at least ${minPlayers} players to start` : ''}
              >
                <Play className="w-5 h-5 mr-2" />
                Start Game
                {playerCount < minPlayers && ` (${playerCount}/${minPlayers})`}
              </button>
            )}

            <button
              onClick={handleLeave}
              className="flex-1 flex items-center justify-center px-6 py-3 bg-slate-700 hover:bg-slate-600 text-white font-semibold rounded-lg transition-colors"
            >
              <ArrowLeft className="w-5 h-5 mr-2" />
              Leave Party
            </button>

            {canDelete && (
              <button
                onClick={handleDelete}
                className="flex-1 flex items-center justify-center px-6 py-3 bg-red-600 hover:bg-red-700 text-white font-semibold rounded-lg transition-colors"
                title={isOnlyHuman && !isOwner ? 'You can delete because you are the only human player' : 'Delete this party'}
              >
                <Trash2 className="w-5 h-5 mr-2" />
                Delete Party
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Fill with bots and start: one level for every free seat */}
      {fillOpen && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="fill-dialog-title"
            className="bg-slate-800 rounded-lg shadow-2xl p-6 border border-slate-700 w-full max-w-sm"
          >
            <h3 id="fill-dialog-title" className="text-xl font-bold text-white mb-2">
              Fill with bots
            </h3>
            <p className="text-gray-300 text-sm mb-4">
              The free seats go to bots of this level, or of the next one when there are not
              enough, then the game starts.
            </p>
            <fieldset className="space-y-2 mb-6">
              <legend className="sr-only">Bot level</legend>
              {FILL_DIFFICULTIES.map(({ value, label }) => (
                <label key={value} className="flex items-center gap-3 p-2 rounded bg-slate-700 text-white cursor-pointer">
                  <input
                    type="radio"
                    name="fill-level"
                    value={value}
                    checked={fillLevel === value}
                    onChange={() => setFillLevel(value)}
                  />
                  {label}
                </label>
              ))}
            </fieldset>
            <div className="flex gap-3">
              <button
                onClick={() => setFillOpen(false)}
                disabled={busy}
                className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleFillAndStart}
                disabled={busy}
                className="flex-1 flex items-center justify-center px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors disabled:opacity-60"
              >
                <Play className="w-4 h-4 mr-2" />
                Start
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default PartyLobby;
