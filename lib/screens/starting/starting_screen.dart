import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/backend_launcher.dart';
import '../../theme/app_colors.dart';

/// Standalone Windows desktop build only (Phase 9) -- shown before the
/// splash screen while the embedded backend.exe subprocess starts and
/// becomes ready (BackendLauncherController). Never reachable on the
/// web build or any other platform (see app_router.dart's
/// initialLocation, which only ever points here on desktop).
///
/// Deliberately a SEPARATE screen from SplashScreen rather than
/// extending that screen's own hold-until-ready logic: SplashScreen's
/// "hold" is a fixed animation timer with no existing readiness concept
/// to extend, and its state machine (glare sweep, particle field, fade
/// transitions) is intricate enough that bolting backend-readiness onto
/// it would risk destabilizing carefully-tuned animation code for no
/// real benefit -- a plain, separate screen ahead of it is simpler and
/// exactly as correct.
class StartingScreen extends ConsumerWidget {
  const StartingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(backendLauncherProvider, (previous, next) {
      if (next.status == BackendLaunchStatus.ready) {
        context.go('/splash');
      }
    });
    final state = ref.watch(backendLauncherProvider);
    // ref.listen only fires on a state *transition* -- if the provider is
    // already ready by this widget's first build (a fast/warm backend, or
    // a test double that starts pre-ready), that transition already
    // happened before anyone was listening and would otherwise strand
    // this screen forever. Schedule the same navigation for that case too.
    if (state.status == BackendLaunchStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/splash');
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bodyBackground,
      body: Center(
        child: state.status == BackendLaunchStatus.failed
            ? _FailedState(state: state)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 20),
                  Text('Starting Bank Working Generator...',
                      style: TextStyle(color: AppColors.text, fontSize: 14)),
                ],
              ),
      ),
    );
  }
}

class _FailedState extends StatelessWidget {
  const _FailedState({required this.state});

  final BackendLaunchState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: AppColors.red, size: 40),
          const SizedBox(height: 16),
          Text('The application backend failed to start.',
              style: TextStyle(color: AppColors.heading, fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(state.errorMessage ?? 'Unknown error.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5), textAlign: TextAlign.center),
          if (state.logPath != null) ...[
            const SizedBox(height: 10),
            Text('See the log at:\n${state.logPath}',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
