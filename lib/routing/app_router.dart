import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../screens/starting/starting_screen.dart';
import '../screens/summary/summary_screen.dart';
import '../screens/templates/template_manager_screen.dart';
import '../screens/upload/upload_screen.dart';
import '../state/auth_state.dart';

/// Standalone Windows desktop build only (Phase 9) -- gates whether
/// /starting (wait for the embedded backend subprocess) is even in the
/// startup path. The web build and every other platform go straight to
/// /splash exactly as before this feature existed.
bool get _isDesktopBuild => !kIsWeb && Platform.isWindows;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: _isDesktopBuild ? '/starting' : '/splash',
    refreshListenable: _AuthChangeNotifier(ref),
    redirect: (context, state) {
      // /starting (desktop only) and /splash both always play once on
      // launch regardless of auth state -- they drive their own timing
      // and hand off via context.go(...), so the auth redirect below
      // must not pre-empt either.
      if (state.matchedLocation == '/starting') return null;
      if (state.matchedLocation == '/splash') return null;

      final authState = ref.read(authControllerProvider);
      if (authState.isLoading) return null;
      final loggingIn = state.matchedLocation == '/login';
      if (!authState.isAuthenticated && !loggingIn) return '/login';
      // Upload is the actual start of the workflow -- dashboard is an
      // analytics view a fresh session has nothing to show yet.
      if (authState.isAuthenticated && loggingIn) return '/upload';
      return null;
    },
    routes: [
      GoRoute(path: '/starting', builder: (context, state) => const StartingScreen()),
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
