import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/admin/admin_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/dataset/dataset_manager_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/review/review_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/summary/summary_screen.dart';
import '../screens/templates/template_manager_screen.dart';
import '../screens/upload/upload_screen.dart';
import '../state/auth_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthChangeNotifier(ref),
    redirect: (context, state) {
      // The splash screen (HTML source: #splashOverlay) always plays once
      // on launch regardless of auth state — it drives its own timing and
      // hands off via onComplete, so the auth redirect below must not
      // pre-empt it.
      if (state.matchedLocation == '/splash') return null;

      final authState = ref.read(authControllerProvider);
      if (authState.isLoading) return null;
      final loggingIn = state.matchedLocation == '/login';
      if (!authState.isAuthenticated && !loggingIn) return '/login';
      if (authState.isAuthenticated && loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => SplashScreen(onComplete: () => context.go('/login')),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/upload', builder: (context, state) => const UploadScreen()),
      GoRoute(path: '/review', builder: (context, state) => const ReviewScreen()),
      GoRoute(path: '/summary', builder: (context, state) => const SummaryScreen()),
      GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/templates', builder: (context, state) => const TemplateManagerScreen()),
      GoRoute(path: '/dataset-manager', builder: (context, state) => const DatasetManagerScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
    ],
  );
});

/// Bridges Riverpod's authControllerProvider into go_router's
/// Listenable-based refresh mechanism, so a login/logout immediately
/// re-runs the redirect above instead of waiting for the next navigation.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}
