import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/parties_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';

/// The route paths, so screens navigate by name rather than by string.
abstract final class AppRoutes {
  static const home = '/';
  static const login = '/login';
  static const register = '/register';
  static const parties = '/parties';
  static const admin = '/admin';

  /// Shown while the stored session is being read at start-up.
  static const splash = '/splash';

  /// Reachable signed out. Everything else needs a session.
  static const public = {home, login, register};

  /// The query parameter carrying where to go once signed in (or restored).
  static const from = 'from';
}

/// The app's routes. A new screen is one more [GoRoute] here; access rules
/// live in [authRedirect], re-run whenever [auth] changes.
GoRouter createRouter({
  required AuthProvider auth,
  String initialLocation = AppRoutes.home,
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: auth,
  redirect: (context, state) => authRedirect(auth, state.uri),
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.register,
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: AppRoutes.parties,
      builder: (context, state) => const PartiesScreen(),
    ),
  ],
  errorBuilder: (context, state) => const NotFoundScreen(),
);

/// Where [uri] really leads for [auth], or `null` to stay:
/// - before the stored session is read, the splash screen, remembering [uri];
/// - signed out (no token, or an expired one), the login screen, remembering
///   [uri]; home, login and register stay reachable;
/// - signed in, login, register and home lead on to the parties (or the
///   remembered path); `/admin/**` needs `isAdmin`, else the parties.
String? authRedirect(AuthProvider auth, Uri uri) {
  final path = uri.path;
  if (!auth.isRestored) {
    return path == AppRoutes.splash ? null : _with(AppRoutes.splash, uri);
  }
  if (path == AppRoutes.splash) {
    return _from(uri) ?? AppRoutes.home;
  }
  if (!auth.isAuthenticated) {
    return AppRoutes.public.contains(path) ? null : _with(AppRoutes.login, uri);
  }
  if (AppRoutes.public.contains(path)) {
    return _from(uri) ?? AppRoutes.parties;
  }
  if ((path == AppRoutes.admin || path.startsWith('${AppRoutes.admin}/')) &&
      !auth.isAdmin) {
    return AppRoutes.parties;
  }
  return null;
}

/// [target] remembering [uri] (unless it is home, the default anyway).
String _with(String target, Uri uri) {
  final from = _from(uri) ?? uri.toString();
  if (from == AppRoutes.home) return target;
  return Uri(path: target, queryParameters: {AppRoutes.from: from}).toString();
}

/// The remembered path, if it is one of this app's (no `//host` or scheme).
String? _from(Uri uri) {
  final from = uri.queryParameters[AppRoutes.from];
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  return from;
}
