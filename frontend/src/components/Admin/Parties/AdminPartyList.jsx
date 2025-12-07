import { useState, useEffect } from 'react';
import { Gamepad2, Trash2, StopCircle, Loader, Filter, AlertCircle, Users, Clock } from 'lucide-react';
import { apiClient } from '../../../services/api';

/**
 * AdminPartyList - Admin party management page
 * Lists all parties with ability to stop and delete them
 */
function AdminPartyList() {
  const [parties, setParties] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [pagination, setPagination] = useState({ total: 0, limit: 50, offset: 0 });
  const [statusFilter, setStatusFilter] = useState('');
  const [actionLoading, setActionLoading] = useState(null);

  useEffect(() => {
    fetchParties();
  }, [pagination.offset, statusFilter]);

  const fetchParties = async () => {
    try {
      setLoading(true);
      setError('');
      const params = { limit: pagination.limit, offset: pagination.offset };
      if (statusFilter) {
        params.status = statusFilter;
      }
      const response = await apiClient.get('/admin/parties', { params });
      setParties(response.data.parties);
      setPagination(prev => ({ ...prev, total: response.data.pagination.total }));
    } catch (err) {
      console.error('Failed to fetch parties:', err);
      setError(err.response?.data?.error || 'Erreur lors du chargement des parties');
    } finally {
      setLoading(false);
    }
  };

  const handleStop = async (partyId, partyName) => {
    if (!confirm(`Arreter la partie "${partyName}" ? Elle sera marquee comme terminee.`)) {
      return;
    }

    try {
      setActionLoading(partyId);
      await apiClient.post(`/admin/parties/${partyId}/stop`);
      fetchParties();
    } catch (err) {
      alert(err.response?.data?.error || 'Erreur lors de arret');
    } finally {
      setActionLoading(null);
    }
  };

  const handleDelete = async (partyId, partyName) => {
    if (!confirm(`Supprimer la partie "${partyName}" et toutes ses donnees ? Cette action est irreversible.`)) {
      return;
    }

    try {
      setActionLoading(partyId);
      await apiClient.delete(`/admin/parties/${partyId}`);
      fetchParties();
    } catch (err) {
      alert(err.response?.data?.error || 'Erreur lors de la suppression');
    } finally {
      setActionLoading(null);
    }
  };

  const formatDate = (timestamp) => {
    if (!timestamp) return '-';
    return new Date(timestamp * 1000).toLocaleDateString('fr-FR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const getStatusBadge = (status) => {
    const styles = {
      waiting: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/50',
      playing: 'bg-green-500/20 text-green-400 border-green-500/50',
      finished: 'bg-gray-500/20 text-gray-400 border-gray-500/50'
    };
    const labels = {
      waiting: 'En attente',
      playing: 'En cours',
      finished: 'Terminee'
    };
    return (
      <span className={`px-2 py-1 text-xs font-medium rounded border ${styles[status] || styles.waiting}`}>
        {labels[status] || status}
      </span>
    );
  };

  const parseSettings = (settingsJson) => {
    try {
      return JSON.parse(settingsJson);
    } catch {
      return { playerCount: '?' };
    }
  };

  if (loading && parties.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader className="w-8 h-8 text-amber-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <h2 className="text-xl font-bold text-white flex items-center">
          <Gamepad2 className="w-6 h-6 text-amber-400 mr-2" />
          Gestion des Parties
          <span className="ml-2 text-sm font-normal text-gray-400">
            ({pagination.total} parties)
          </span>
        </h2>
        <div className="flex items-center space-x-2">
          <Filter className="w-4 h-4 text-gray-400" />
          <select
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setPagination(p => ({ ...p, offset: 0 }));
            }}
            className="bg-slate-700 border border-slate-600 rounded-lg text-white px-3 py-2 focus:outline-none focus:border-amber-500"
          >
            <option value="">Tous les statuts</option>
            <option value="waiting">En attente</option>
            <option value="playing">En cours</option>
            <option value="finished">Terminee</option>
          </select>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-red-500/20 border border-red-500 rounded-lg p-4 flex items-center">
          <AlertCircle className="w-5 h-5 text-red-400 mr-2" />
          <span className="text-red-300">{error}</span>
        </div>
      )}

      {/* Table */}
      <div className="bg-slate-800 rounded-lg border border-slate-700 overflow-hidden overflow-x-auto">
        <table className="w-full min-w-[900px]">
          <thead className="bg-slate-700">
            <tr>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Nom</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Proprietaire</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Statut</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Joueurs</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Visibilite</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Creee le</th>
              <th className="px-4 py-3 text-right text-sm font-medium text-gray-300">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-700">
            {parties.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-gray-400">
                  Aucune partie trouvee
                </td>
              </tr>
            ) : (
              parties.map((party) => {
                const settings = parseSettings(party.settings);
                return (
                  <tr key={party.id} className="hover:bg-slate-700/50 transition-colors">
                    <td className="px-4 py-3">
                      <div className="text-white font-medium">{party.name}</div>
                      <div className="text-gray-500 text-xs">{party.inviteCode}</div>
                    </td>
                    <td className="px-4 py-3 text-gray-300">{party.ownerUsername}</td>
                    <td className="px-4 py-3">{getStatusBadge(party.status)}</td>
                    <td className="px-4 py-3">
                      <div className="flex items-center text-gray-400">
                        <Users className="w-4 h-4 mr-1" />
                        {party.playerCount} / {settings.playerCount}
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`text-sm ${party.visibility === 'public' ? 'text-green-400' : 'text-gray-400'}`}>
                        {party.visibility === 'public' ? 'Publique' : 'Privee'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-gray-400 text-sm">
                      <div className="flex items-center">
                        <Clock className="w-4 h-4 mr-1" />
                        {formatDate(party.createdAt)}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex items-center justify-end space-x-2">
                        {party.status !== 'finished' && (
                          <button
                            onClick={() => handleStop(party.id, party.name)}
                            disabled={actionLoading === party.id}
                            className="p-2 text-gray-400 hover:text-yellow-400 hover:bg-slate-600 rounded transition-colors disabled:opacity-50"
                            title="Arreter la partie"
                          >
                            {actionLoading === party.id ? (
                              <Loader className="w-4 h-4 animate-spin" />
                            ) : (
                              <StopCircle className="w-4 h-4" />
                            )}
                          </button>
                        )}
                        <button
                          onClick={() => handleDelete(party.id, party.name)}
                          disabled={actionLoading === party.id}
                          className="p-2 text-gray-400 hover:text-red-400 hover:bg-slate-600 rounded transition-colors disabled:opacity-50"
                          title="Supprimer la partie"
                        >
                          {actionLoading === party.id ? (
                            <Loader className="w-4 h-4 animate-spin" />
                          ) : (
                            <Trash2 className="w-4 h-4" />
                          )}
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      {pagination.total > pagination.limit && (
        <div className="flex justify-center items-center space-x-4">
          <button
            disabled={pagination.offset === 0}
            onClick={() => setPagination(p => ({ ...p, offset: Math.max(0, p.offset - p.limit) }))}
            className="px-4 py-2 bg-slate-700 text-white rounded-lg hover:bg-slate-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Precedent
          </button>
          <span className="text-gray-400 text-sm">
            {pagination.offset + 1} - {Math.min(pagination.offset + pagination.limit, pagination.total)} sur {pagination.total}
          </span>
          <button
            disabled={pagination.offset + pagination.limit >= pagination.total}
            onClick={() => setPagination(p => ({ ...p, offset: p.offset + p.limit }))}
            className="px-4 py-2 bg-slate-700 text-white rounded-lg hover:bg-slate-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Suivant
          </button>
        </div>
      )}
    </div>
  );
}

export default AdminPartyList;
