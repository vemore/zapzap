import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/not_found_screen.dart';

/// The route paths, so screens navigate by name rather than by string.
abstract final class AppRoutes {
  static const home = '/';
  static const login = '/login';
}

/// The app's routes. A new screen is one more [GoRoute] here; redirects
/// (such as "signed out goes to login") belong in [GoRouter.redirect].
GoRouter createRouter({String initialLocation = AppRoutes.home}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
  ],
  errorBuilder: (context, state) => const NotFoundScreen(),
);
