import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'services/backend_launcher.dart';
import 'theme/app_theme.dart';

void main() {
  // Needed now that async work (the desktop build's embedded-backend
  // launch, via backend_launcher.dart) can start before the first
  // frame -- previously nothing here required binding initialization.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: BankWorkingDesktopApp()));
}

class BankWorkingDesktopApp extends ConsumerStatefulWidget {
  const BankWorkingDesktopApp({super.key});

  @override
  ConsumerState<BankWorkingDesktopApp> createState() => _BankWorkingDesktopAppState();
}

class _BankWorkingDesktopAppState extends ConsumerState<BankWorkingDesktopApp> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Standalone Windows desktop build only (Phase 9) -- kill the
    // embedded backend subprocess on a graceful window close. See
    // backend_launcher.dart's shutdown()/BackendLauncherController
    // docstring for the known gap on a hard kill (Task Manager "End
    // Task"), accepted for v1.
    if (!kIsWeb && Platform.isWindows) {
      _lifecycleListener = AppLifecycleListener(
        onExitRequested: () async {
          await ref.read(backendLauncherProvider.notifier).shutdown();
          return AppExitResponse.exit;
        },
      );
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Bank Working Generator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
