import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Standalone Windows desktop build only (Phase 9) -- spawns the
/// bundled backend.exe as a local subprocess on startup, waits until
/// it's actually serving (GET /ready), and kills it on app shutdown.
/// Never constructed on web or any other platform -- see AppShell/
/// main.dart's `!kIsWeb && Platform.isWindows` gating, the same pattern
/// auth_state.dart's desktop auto-login already uses.
enum BackendLaunchStatus { starting, ready, failed }

class BackendLaunchState {
  const BackendLaunchState({this.status = BackendLaunchStatus.starting, this.errorMessage, this.logPath});

  final BackendLaunchStatus status;
  final String? errorMessage;
  final String? logPath;

  BackendLaunchState copyWith({BackendLaunchStatus? status, String? errorMessage, String? logPath}) {
    return BackendLaunchState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      logPath: logPath ?? this.logPath,
    );
  }
}

class BackendLauncherController extends StateNotifier<BackendLaunchState> {
  /// [autoLaunch] and [initialState] exist only so tests can override
  /// [backendLauncherProvider] with an instance that never spawns a real
  /// subprocess -- see widget_test.dart. Production call sites always use
  /// the defaults.
  BackendLauncherController({bool autoLaunch = true, BackendLaunchState initialState = const BackendLaunchState()})
      : super(initialState) {
    if (autoLaunch) _launch();
  }

  /// Fixed for v1 -- matches api_client.dart's existing compile-time
  /// default (`String.fromEnvironment('API_BASE_URL', ...)`), which
  /// isn't something a runtime-resolved dynamic port could feed into
  /// without reworking that constant. A real port conflict on an
  /// end-user machine is possible but low-probability; flagged as a
  /// known v1 limitation, not solved here.
  static const _port = 8000;

  Process? _process;
  IOSink? _logSink;

  Future<void> _launch() async {
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null) {
        state = state.copyWith(status: BackendLaunchStatus.failed, errorMessage: 'LOCALAPPDATA is not set.');
        return;
      }
      final appDataRoot = '$localAppData\\BankWorkingDesktop';
      final logsDir = Directory('$appDataRoot\\logs');
      await logsDir.create(recursive: true);
      final logPath = '${logsDir.path}\\backend-launcher.log';
      _logSink = File(logPath).openWrite(mode: FileMode.append);
      _logSink!.writeln('--- launch at ${DateTime.now().toIso8601String()} ---');

      // The Inno Setup layout (Phase 9 Phase 5) places the backend as a
      // sibling folder to the Flutter exe: {app}\backend\backend.exe,
      // {app}\backend\_internal\alembic.ini.
      final installDir = File(Platform.resolvedExecutable).parent;
      final backendExePath = '${installDir.path}\\backend\\backend.exe';
      final alembicIniDir = '${installDir.path}\\backend\\_internal';

      if (!await File(backendExePath).exists()) {
        state = state.copyWith(
          status: BackendLaunchStatus.failed,
          errorMessage: 'Backend executable not found at $backendExePath.',
          logPath: logPath,
        );
        return;
      }

      _process = await Process.start(
        backendExePath,
        [],
        environment: {'APP_DATA_ROOT': appDataRoot, 'ALEMBIC_INI_DIR': alembicIniDir},
        mode: ProcessStartMode.normal,
      );
      _process!.stdout.transform(const SystemEncoding().decoder).listen(_logSink!.write);
      _process!.stderr.transform(const SystemEncoding().decoder).listen(_logSink!.write);

      await _waitUntilReady(logPath);
    } catch (error) {
      state = state.copyWith(status: BackendLaunchStatus.failed, errorMessage: error.toString());
    }
  }

  Future<void> _waitUntilReady(String logPath) async {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2), receiveTimeout: const Duration(seconds: 2)));
    // ~45s at 300ms/attempt -- budgets for first-run Alembic migrations
    // against a fresh SQLite file, not just process startup.
    const maxAttempts = 150;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await dio.get('http://127.0.0.1:$_port/ready');
        if (response.statusCode == 200) {
          state = state.copyWith(status: BackendLaunchStatus.ready);
          return;
        }
      } on DioException {
        // Not up yet -- expected on every attempt but the last.
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    state = state.copyWith(
      status: BackendLaunchStatus.failed,
      errorMessage: 'The backend did not become ready in time.',
      logPath: logPath,
    );
  }

  /// Called from the window-close handler (main.dart) -- SIGTERM first,
  /// escalating to SIGKILL after a short grace period if still alive.
  /// Known gap, accepted for v1: Windows doesn't auto-kill a child
  /// process when its parent is hard-killed (Task Manager "End Task")
  /// the way POSIX process groups do, and Dart doesn't expose Job
  /// Object binding to close that gap. Low-impact given the backend
  /// only binds to 127.0.0.1 with no visible window -- the next launch's
  /// own /ready check (or a port-bind failure) surfaces the problem
  /// loudly rather than silently, if it ever happens.
  Future<void> shutdown() async {
    final process = _process;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    await Future.any([process.exitCode, Future.delayed(const Duration(seconds: 3))]);
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      // Already exited -- kill() on a dead process is a harmless no-op race.
    }
    await _logSink?.flush();
    await _logSink?.close();
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}

final backendLauncherProvider = StateNotifierProvider<BackendLauncherController, BackendLaunchState>(
  (ref) => BackendLauncherController(),
);
