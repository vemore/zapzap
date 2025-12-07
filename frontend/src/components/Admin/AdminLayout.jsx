import { Link, Outlet, useLocation } from 'react-router-dom';
import { Users, Gamepad2, BarChart3, Shield, ArrowLeft } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';

/**
 * AdminLayout - Layout component for admin pages
 * Provides navigation header and renders child routes
 */
function AdminLayout() {
  const location = useLocation();
  const { user } = useAuth();

  const navItems = [
    { path: '/admin/users', label: 'Utilisateurs', icon: Users },
    { path: '/admin/parties', label: 'Parties', icon: Gamepad2 },
    { path: '/admin/statistics', label: 'Statistiques', icon: BarChart3 },
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-amber-900/50 to-slate-700 border-b border-amber-600/50 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div className="flex items-center">
              <Shield className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">Admin Panel</h1>
            </div>
            <div className="flex items-center space-x-4">
              <span className="text-gray-400 text-sm">
                Connecte en tant que <span className="text-amber-400">{user?.username}</span>
              </span>
              <Link
                to="/parties"
                className="flex items-center text-gray-300 hover:text-white transition-colors px-3 py-2 rounded-lg hover:bg-slate-700"
              >
                <ArrowLeft className="w-4 h-4 mr-1" />
                Retour au jeu
              </Link>
            </div>
          </div>
        </div>
      </div>

      {/* Sub Navigation */}
      <div className="bg-slate-800 border-b border-slate-700">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <nav className="flex space-x-1">
            {navItems.map(({ path, label, icon: Icon }) => (
              <Link
                key={path}
                to={path}
                className={`flex items-center px-4 py-3 text-sm font-medium transition-colors border-b-2 ${
                  location.pathname === path
                    ? 'text-amber-400 border-amber-400 bg-slate-700/50'
                    : 'text-gray-400 border-transparent hover:text-white hover:bg-slate-700/30'
                }`}
              >
                <Icon className="w-4 h-4 mr-2" />
                {label}
              </Link>
            ))}
          </nav>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
        <Outlet />
      </div>
    </div>
  );
}

export default AdminLayout;
