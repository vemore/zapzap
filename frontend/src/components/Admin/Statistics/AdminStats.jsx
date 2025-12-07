import { useState, useEffect, useRef } from 'react';
import { BarChart3, Users, Gamepad2, CircleDot, Loader, AlertCircle, TrendingUp, Trophy } from 'lucide-react';
import { apiClient } from '../../../services/api';

/**
 * AdminStats - Admin statistics dashboard
 * Shows platform metrics, charts, and most active users
 */
function AdminStats() {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const canvasRef = useRef(null);

  useEffect(() => {
    fetchStats();
  }, []);

  useEffect(() => {
    if (stats && canvasRef.current) {
      drawChart();
    }
  }, [stats]);

  const fetchStats = async () => {
    try {
      setLoading(true);
      setError('');
      const response = await apiClient.get('/admin/statistics');
      setStats(response.data.stats);
    } catch (err) {
      console.error('Failed to fetch statistics:', err);
      setError(err.response?.data?.error || 'Erreur lors du chargement des statistiques');
    } finally {
      setLoading(false);
    }
  };

  const drawChart = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    const data = stats.gamesOverTime.daily.filter(d => d.period !== null);

    if (data.length === 0) {
      ctx.fillStyle = '#6b7280';
      ctx.font = '14px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('Pas assez de donnees', canvas.width / 2, canvas.height / 2);
      return;
    }

    // Clear canvas
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    const padding = { top: 20, right: 20, bottom: 40, left: 50 };
    const chartWidth = canvas.width - padding.left - padding.right;
    const chartHeight = canvas.height - padding.top - padding.bottom;

    const maxValue = Math.max(...data.map(d => d.count), 1);
    const barWidth = Math.min(40, (chartWidth / data.length) - 10);
    const spacing = (chartWidth - barWidth * data.length) / (data.length + 1);

    // Draw axes
    ctx.strokeStyle = '#475569';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(padding.left, padding.top);
    ctx.lineTo(padding.left, canvas.height - padding.bottom);
    ctx.lineTo(canvas.width - padding.right, canvas.height - padding.bottom);
    ctx.stroke();

    // Draw Y-axis labels
    ctx.fillStyle = '#9ca3af';
    ctx.font = '12px sans-serif';
    ctx.textAlign = 'right';
    for (let i = 0; i <= 4; i++) {
      const value = Math.round((maxValue * i) / 4);
      const y = canvas.height - padding.bottom - (chartHeight * i) / 4;
      ctx.fillText(value.toString(), padding.left - 10, y + 4);

      // Draw grid line
      ctx.strokeStyle = '#374151';
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(canvas.width - padding.right, y);
      ctx.stroke();
    }

    // Draw bars
    data.forEach((d, i) => {
      const x = padding.left + spacing + i * (barWidth + spacing);
      const barHeight = (d.count / maxValue) * chartHeight;
      const y = canvas.height - padding.bottom - barHeight;

      // Bar gradient
      const gradient = ctx.createLinearGradient(x, y, x, canvas.height - padding.bottom);
      gradient.addColorStop(0, '#f59e0b');
      gradient.addColorStop(1, '#b45309');

      ctx.fillStyle = gradient;
      ctx.fillRect(x, y, barWidth, barHeight);

      // X-axis label (date)
      ctx.fillStyle = '#9ca3af';
      ctx.font = '10px sans-serif';
      ctx.textAlign = 'center';
      const dateLabel = d.period ? d.period.slice(-5) : '-';
      ctx.fillText(dateLabel, x + barWidth / 2, canvas.height - padding.bottom + 15);

      // Value on top of bar
      if (d.count > 0) {
        ctx.fillStyle = '#f59e0b';
        ctx.font = 'bold 11px sans-serif';
        ctx.fillText(d.count.toString(), x + barWidth / 2, y - 5);
      }
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader className="w-8 h-8 text-amber-400 animate-spin" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-500/20 border border-red-500 rounded-lg p-4 flex items-center">
        <AlertCircle className="w-5 h-5 text-red-400 mr-2" />
        <span className="text-red-300">{error}</span>
      </div>
    );
  }

  if (!stats) {
    return null;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <h2 className="text-xl font-bold text-white flex items-center">
        <BarChart3 className="w-6 h-6 text-amber-400 mr-2" />
        Statistiques de la Plateforme
      </h2>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          icon={Users}
          label="Utilisateurs"
          value={stats.users.total}
          color="amber"
        />
        <StatCard
          icon={Gamepad2}
          label="Parties totales"
          value={stats.parties.total}
          color="blue"
        />
        <StatCard
          icon={CircleDot}
          label="Rounds joues"
          value={stats.rounds.total}
          color="green"
        />
        <StatCard
          icon={TrendingUp}
          label="Taux de completion"
          value={`${stats.parties.completionRate}%`}
          color="purple"
        />
      </div>

      {/* Party Status Breakdown */}
      <div className="bg-slate-800 rounded-lg border border-slate-700 p-6">
        <h3 className="text-lg font-semibold text-white mb-4">Repartition des Parties</h3>
        <div className="grid grid-cols-3 gap-4">
          <div className="text-center p-4 bg-slate-700/50 rounded-lg">
            <div className="text-2xl font-bold text-yellow-400">{stats.parties.waiting}</div>
            <div className="text-sm text-gray-400">En attente</div>
          </div>
          <div className="text-center p-4 bg-slate-700/50 rounded-lg">
            <div className="text-2xl font-bold text-green-400">{stats.parties.playing}</div>
            <div className="text-sm text-gray-400">En cours</div>
          </div>
          <div className="text-center p-4 bg-slate-700/50 rounded-lg">
            <div className="text-2xl font-bold text-gray-400">{stats.parties.finished}</div>
            <div className="text-sm text-gray-400">Terminees</div>
          </div>
        </div>
      </div>

      {/* Games Over Time Chart */}
      <div className="bg-slate-800 rounded-lg border border-slate-700 p-6">
        <h3 className="text-lg font-semibold text-white mb-4">
          Evolution des Parties (30 derniers jours)
        </h3>
        <div className="relative">
          <canvas
            ref={canvasRef}
            width={800}
            height={300}
            className="w-full h-auto"
            style={{ maxHeight: '300px' }}
          />
        </div>
      </div>

      {/* Most Active Users */}
      <div className="bg-slate-800 rounded-lg border border-slate-700 p-6">
        <h3 className="text-lg font-semibold text-white mb-4 flex items-center">
          <Trophy className="w-5 h-5 text-amber-400 mr-2" />
          Joueurs les Plus Actifs
        </h3>
        {stats.mostActiveUsers.length === 0 ? (
          <p className="text-gray-400">Aucun joueur avec des parties terminees</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-gray-400 text-sm border-b border-slate-700">
                  <th className="pb-3 font-medium">#</th>
                  <th className="pb-3 font-medium">Joueur</th>
                  <th className="pb-3 font-medium text-right">Parties</th>
                  <th className="pb-3 font-medium text-right">Victoires</th>
                  <th className="pb-3 font-medium text-right">Taux</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-700">
                {stats.mostActiveUsers.map((user, index) => (
                  <tr key={user.userId} className="text-gray-300">
                    <td className="py-3">
                      <span className={`
                        ${index === 0 ? 'text-amber-400' : ''}
                        ${index === 1 ? 'text-gray-300' : ''}
                        ${index === 2 ? 'text-orange-600' : ''}
                        font-semibold
                      `}>
                        {index + 1}
                      </span>
                    </td>
                    <td className="py-3 font-medium text-white">{user.username}</td>
                    <td className="py-3 text-right">{user.gamesPlayed}</td>
                    <td className="py-3 text-right text-green-400">{user.wins}</td>
                    <td className="py-3 text-right">
                      {user.gamesPlayed > 0
                        ? `${((user.wins / user.gamesPlayed) * 100).toFixed(0)}%`
                        : '-'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

/**
 * StatCard - Reusable stat card component
 */
function StatCard({ icon: Icon, label, value, color }) {
  const colorClasses = {
    amber: 'text-amber-400 bg-amber-400/10',
    blue: 'text-blue-400 bg-blue-400/10',
    green: 'text-green-400 bg-green-400/10',
    purple: 'text-purple-400 bg-purple-400/10'
  };

  return (
    <div className="bg-slate-800 rounded-lg border border-slate-700 p-6">
      <div className="flex items-center">
        <div className={`p-3 rounded-lg ${colorClasses[color]}`}>
          <Icon className="w-6 h-6" />
        </div>
        <div className="ml-4">
          <div className="text-2xl font-bold text-white">{value}</div>
          <div className="text-sm text-gray-400">{label}</div>
        </div>
      </div>
    </div>
  );
}

export default AdminStats;
