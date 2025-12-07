import { useState, useEffect } from 'react';
import { Users, Trash2, Shield, ShieldOff, Loader, Search, AlertCircle } from 'lucide-react';
import { apiClient } from '../../../services/api';
import { useAuth } from '../../../contexts/AuthContext';

/**
 * UserList - Admin user management page
 * Lists all users with ability to delete and grant/revoke admin rights
 */
function UserList() {
  const { user: currentUser } = useAuth();
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [pagination, setPagination] = useState({ total: 0, limit: 50, offset: 0 });
  const [searchTerm, setSearchTerm] = useState('');
  const [actionLoading, setActionLoading] = useState(null);

  useEffect(() => {
    fetchUsers();
  }, [pagination.offset]);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      setError('');
      const response = await apiClient.get('/admin/users', {
        params: { limit: pagination.limit, offset: pagination.offset }
      });
      setUsers(response.data.users);
      setPagination(prev => ({ ...prev, total: response.data.pagination.total }));
    } catch (err) {
      console.error('Failed to fetch users:', err);
      setError(err.response?.data?.error || 'Erreur lors du chargement des utilisateurs');
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (userId, username) => {
    if (!confirm(`Supprimer l'utilisateur "${username}" ? Cette action est irreversible.`)) {
      return;
    }

    try {
      setActionLoading(userId);
      await apiClient.delete(`/admin/users/${userId}`);
      fetchUsers();
    } catch (err) {
      alert(err.response?.data?.error || 'Erreur lors de la suppression');
    } finally {
      setActionLoading(null);
    }
  };

  const handleToggleAdmin = async (userId, currentIsAdmin) => {
    const action = currentIsAdmin ? 'retirer les droits admin de' : 'donner les droits admin a';
    const user = users.find(u => u.id === userId);

    if (!confirm(`${action} "${user?.username}" ?`)) {
      return;
    }

    try {
      setActionLoading(userId);
      await apiClient.post(`/admin/users/${userId}/admin`, {
        isAdmin: !currentIsAdmin
      });
      fetchUsers();
    } catch (err) {
      alert(err.response?.data?.error || 'Erreur lors de la modification');
    } finally {
      setActionLoading(null);
    }
  };

  const formatDate = (timestamp) => {
    if (!timestamp) return 'Jamais';
    return new Date(timestamp * 1000).toLocaleDateString('fr-FR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const formatPlayTime = (seconds) => {
    if (!seconds) return '0h';
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    if (hours === 0) return `${minutes}m`;
    return `${hours}h ${minutes}m`;
  };

  const filteredUsers = users.filter(u =>
    u.username.toLowerCase().includes(searchTerm.toLowerCase())
  );

  if (loading && users.length === 0) {
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
          <Users className="w-6 h-6 text-amber-400 mr-2" />
          Gestion des Utilisateurs
          <span className="ml-2 text-sm font-normal text-gray-400">
            ({pagination.total} utilisateurs)
          </span>
        </h2>
        <div className="relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Rechercher..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="pl-10 pr-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:border-amber-500 w-full sm:w-64"
          />
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
        <table className="w-full min-w-[800px]">
          <thead className="bg-slate-700">
            <tr>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Utilisateur</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Cree le</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Derniere connexion</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Parties</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Temps de jeu</th>
              <th className="px-4 py-3 text-left text-sm font-medium text-gray-300">Admin</th>
              <th className="px-4 py-3 text-right text-sm font-medium text-gray-300">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-700">
            {filteredUsers.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-gray-400">
                  {searchTerm ? 'Aucun utilisateur trouve' : 'Aucun utilisateur'}
                </td>
              </tr>
            ) : (
              filteredUsers.map((u) => (
                <tr key={u.id} className="hover:bg-slate-700/50 transition-colors">
                  <td className="px-4 py-3">
                    <span className="text-white font-medium">{u.username}</span>
                    {u.id === currentUser?.id && (
                      <span className="ml-2 text-xs text-amber-400 bg-amber-400/20 px-2 py-0.5 rounded">Vous</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-gray-400 text-sm">{formatDate(u.createdAt)}</td>
                  <td className="px-4 py-3 text-gray-400 text-sm">{formatDate(u.lastLoginAt)}</td>
                  <td className="px-4 py-3 text-gray-400">{u.gamesPlayed || 0}</td>
                  <td className="px-4 py-3 text-gray-400">{formatPlayTime(u.totalPlayTimeSeconds)}</td>
                  <td className="px-4 py-3">
                    {u.isAdmin ? (
                      <span className="text-amber-400 flex items-center text-sm">
                        <Shield className="w-4 h-4 mr-1" /> Oui
                      </span>
                    ) : (
                      <span className="text-gray-500 text-sm">Non</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right">
                    {u.id !== currentUser?.id && u.username !== 'admin' && (
                      <div className="flex items-center justify-end space-x-2">
                        <button
                          onClick={() => handleToggleAdmin(u.id, u.isAdmin)}
                          disabled={actionLoading === u.id}
                          className="p-2 text-gray-400 hover:text-amber-400 hover:bg-slate-600 rounded transition-colors disabled:opacity-50"
                          title={u.isAdmin ? 'Retirer Admin' : 'Donner Admin'}
                        >
                          {actionLoading === u.id ? (
                            <Loader className="w-4 h-4 animate-spin" />
                          ) : u.isAdmin ? (
                            <ShieldOff className="w-4 h-4" />
                          ) : (
                            <Shield className="w-4 h-4" />
                          )}
                        </button>
                        <button
                          onClick={() => handleDelete(u.id, u.username)}
                          disabled={actionLoading === u.id}
                          className="p-2 text-gray-400 hover:text-red-400 hover:bg-slate-600 rounded transition-colors disabled:opacity-50"
                          title="Supprimer"
                        >
                          {actionLoading === u.id ? (
                            <Loader className="w-4 h-4 animate-spin" />
                          ) : (
                            <Trash2 className="w-4 h-4" />
                          )}
                        </button>
                      </div>
                    )}
                  </td>
                </tr>
              ))
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

export default UserList;
