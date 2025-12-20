import { useState, useEffect, useCallback } from 'react';
import { Users, Circle, ChevronDown, ChevronUp } from 'lucide-react';
import { apiClient } from '../../services/api';
import useSSE from '../../hooks/useSSE';

/**
 * Status badge colors and labels
 */
const STATUS_CONFIG = {
  lobby: {
    color: 'bg-green-500',
    label: 'Lobby',
    textColor: 'text-green-400'
  },
  party: {
    color: 'bg-yellow-500',
    label: 'Party',
    textColor: 'text-yellow-400'
  },
  game: {
    color: 'bg-red-500',
    label: 'En jeu',
    textColor: 'text-red-400'
  }
};

/**
 * ConnectedPlayers - Displays the last 5 connected players with their status
 */
function ConnectedPlayers() {
  const [players, setPlayers] = useState([]);
  const [isExpanded, setIsExpanded] = useState(false);
  const [loading, setLoading] = useState(true);

  // Fetch initial connected players
  const fetchPlayers = useCallback(async () => {
    try {
      const response = await apiClient.get('/players/connected');
      setPlayers(response.data.players || []);
    } catch (err) {
      console.error('Failed to fetch connected players:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  // Fetch on mount
  useEffect(() => {
    fetchPlayers();
  }, [fetchPlayers]);

  // Handle SSE events for real-time updates
  const handleSSEMessage = useCallback((data) => {
    if (data.type === 'userConnected') {
      setPlayers(prev => {
        // Add new user at the beginning, remove if already exists
        const filtered = prev.filter(p => p.userId !== data.userId);
        const newPlayer = {
          userId: data.userId,
          username: data.username,
          status: 'lobby',
          partyId: null,
          connectedAt: data.timestamp
        };
        return [newPlayer, ...filtered].slice(0, 5);
      });
    } else if (data.type === 'userDisconnected') {
      setPlayers(prev => prev.filter(p => p.userId !== data.userId));
    } else if (data.type === 'userStatusChanged') {
      setPlayers(prev => prev.map(p =>
        p.userId === data.userId
          ? { ...p, status: data.status, partyId: data.partyId }
          : p
      ));
    }
  }, []);

  // Connect to SSE with token
  const token = localStorage.getItem('token');
  const sseUrl = token ? `/suscribeupdate?token=${encodeURIComponent(token)}` : null;

  useSSE(sseUrl, {
    onMessage: handleSSEMessage
  });

  // Don't render if no players or loading
  if (loading) {
    return null;
  }

  const playerCount = players.length;

  return (
    <div className="relative">
      {/* Toggle button */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="flex items-center px-3 py-2 text-gray-300 hover:text-white hover:bg-slate-600 rounded-lg transition-colors"
      >
        <Users className="w-4 h-4 mr-1" />
        <span className="text-sm font-medium">{playerCount}</span>
        {isExpanded ? (
          <ChevronUp className="w-3 h-3 ml-1" />
        ) : (
          <ChevronDown className="w-3 h-3 ml-1" />
        )}
      </button>

      {/* Dropdown */}
      {isExpanded && (
        <div className="absolute right-0 top-full mt-2 w-56 bg-slate-800 border border-slate-600 rounded-lg shadow-xl z-50">
          <div className="px-3 py-2 border-b border-slate-600">
            <h4 className="text-sm font-semibold text-white">Joueurs connectes</h4>
          </div>

          {playerCount === 0 ? (
            <div className="px-3 py-4 text-center text-gray-400 text-sm">
              Aucun joueur connecte
            </div>
          ) : (
            <ul className="py-1">
              {players.map((player) => {
                const statusConfig = STATUS_CONFIG[player.status] || STATUS_CONFIG.lobby;
                return (
                  <li
                    key={player.userId}
                    className="px-3 py-2 hover:bg-slate-700 flex items-center justify-between"
                  >
                    <span className="text-white text-sm truncate max-w-[120px]">
                      {player.username}
                    </span>
                    <div className="flex items-center">
                      <Circle className={`w-2 h-2 ${statusConfig.color} fill-current mr-1`} />
                      <span className={`text-xs ${statusConfig.textColor}`}>
                        {statusConfig.label}
                      </span>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

export default ConnectedPlayers;
