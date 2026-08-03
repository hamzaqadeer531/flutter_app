import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../models/auth_models.dart';

const _accessTokenKey = 'access_token';
const _refreshTokenKey = 'refresh_token';

/// Thrown for the two documented /auth/login failure responses so the
/// Login screen can show the right message instead of a generic error.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
}

class AuthState {
  const AuthState({this.user, this.isLoading = false});

  final AuthenticatedUser? user;
  final bool isLoading;

  bool get isAuthenticated => user != null;

  AuthState copyWith({AuthenticatedUser? user, bool? isLoading, bool clearUser = false}) => AuthState(
        user: clearUser ? null : (user ?? this.user),
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._apiClient, this._storage) : super(const AuthState(isLoading: true)) {
    _apiClient.dio.interceptors.add(InterceptorsWrapper(onError: _handleDioError));
    _restoreSession();
  }

  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;

  /// Access tokens are short-lived (20 minutes server-side — see
  /// config.py's access_token_expire_minutes) — any authenticated screen
  /// left open past that gets a 401 on its next call. Transparently
  /// rotates the refresh token and retries the failed request once;
  /// only falls back to signing the user out if the refresh token
  /// itself is also invalid, expired, or already used.
  Future<void> _handleDioError(DioException error, ErrorInterceptorHandler handler) async {
    final isUnauthorized = error.response?.statusCode == 401;
    final isRefreshCall = error.requestOptions.path == '/auth/refresh';
    if (!isUnauthorized || isRefreshCall) {
      return handler.next(error);
    }

    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      await _forceSignOutAndRecover();
      return handler.next(error);
    }

    try {
      final response = await _apiClient.dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
      final token = TokenResponse.fromJson(response.data as Map<String, dynamic>);
      await _persistAndActivate(token);

      // FormData wraps file content in a single-use stream (MultipartFile)
      // -- dio already consumed it sending the original (failed) request,
      // so resending the same FormData object throws instead of actually
      // retrying. That thrown error used to be caught below and treated
      // as a refresh failure, force-signing the user out even though the
      // refresh itself just succeeded -- surfaced as a raw DioException
      // on the Upload screen after a token expired mid-session. The token
      // is valid again now; just let the original 401 propagate so the
      // caller's *next* attempt (e.g. re-clicking "Choose File(s)")
      // succeeds normally, instead of forcing a sign-out.
      if (error.requestOptions.data is FormData) {
        return handler.next(error);
      }

      final retryOptions = error.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer ${token.accessToken}';
      final retryResponse = await _apiClient.dio.fetch(retryOptions);
      return handler.resolve(retryResponse);
    } on DioException {
      await _forceSignOutAndRecover();
      return handler.next(error);
    }
  }

  Future<void> _forceSignOut() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    _apiClient.dio.options.headers.remove('Authorization');
    state = state.copyWith(clearUser: true, isLoading: false);
  }

  /// Clears the stale session, then -- standalone Windows desktop build
  /// only -- immediately re-attempts the bootstrap-credential auto-login
  /// instead of stranding the user on a login screen with no real
  /// credentials to type in (this platform's whole point is "no login
  /// screen, ever" -- see _restoreSession's own comment). Covers a real
  /// scenario: flutter_secure_storage's data file lives outside the
  /// app's install directory (confirmed: `%APPDATA%\CompanyName\
  /// ProductName\flutter_secure_storage.dat`, untouched by uninstall),
  /// so a stale token from a previous install/session can survive a
  /// clean reinstall and get rejected by a freshly-provisioned backend
  /// with no matching user/refresh-token record.
  ///
  /// Only used for INVOLUNTARY sign-outs (a rejected/expired token) --
  /// logout() below calls _forceSignOut() directly, so an explicit "Log
  /// out" click actually logs out instead of bouncing straight back in.
  Future<void> _forceSignOutAndRecover() async {
    await _forceSignOut();
    if (!kIsWeb && Platform.isWindows) {
      await _tryDesktopAutoLogin();
    }
  }

  Future<void> _restoreSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    if (accessToken != null) {
      _apiClient.dio.options.headers['Authorization'] = 'Bearer $accessToken';
      state = AuthState(user: _decodeUser(accessToken), isLoading: false);
      return;
    }

    // Standalone Windows desktop build only (Phase 9) -- the web build
    // (kIsWeb) keeps its real login screen untouched; so does every
    // other platform. A fresh desktop install has no stored token yet,
    // so this is where "double-click, no login screen" actually
    // happens: GET /auth/bootstrap-credential 404s harmlessly unless
    // run_desktop.py's own auto-provisioning wrote a real one (see that
    // file's docstring), so this is a no-op everywhere except a genuine
    // desktop install.
    if (!kIsWeb && Platform.isWindows) {
      final autoLoggedIn = await _tryDesktopAutoLogin();
      if (autoLoggedIn) return;
    }

    state = const AuthState(isLoading: false);
  }

  /// AuthController is created (and this runs) the instant the widget
  /// tree first builds -- routerProvider's _AuthChangeNotifier reads
  /// authControllerProvider to set up its refreshListenable, which
  /// happens before StartingScreen ever gets a chance to build and
  /// trigger backendLauncherProvider's creation (the thing that actually
  /// spawns backend.exe). A single attempt here reliably hits a
  /// connection error on every fresh launch -- confirmed by an actual
  /// run where the backend's own log showed zero auth traffic at all,
  /// meaning the request never even reached the server. Retries with the
  /// same ~45s budget backend_launcher.dart's own /ready poll uses,
  /// rather than giving up after one shot.
  Future<bool> _tryDesktopAutoLogin() async {
    const maxAttempts = 150;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _apiClient.dio.get('/auth/bootstrap-credential');
        final email = response.data['email'] as String;
        final password = response.data['password'] as String;
        await login(email, password);
        return true;
      } on DioException catch (e) {
        // A real 404 means the server IS up but genuinely has no
        // bootstrap credential configured (not a desktop install after
        // all) -- stop immediately rather than retrying for 45s. Any
        // other failure (connection refused, timeout) means the backend
        // subprocess likely isn't up yet -- keep trying.
        if (e.response?.statusCode == 404) return false;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    return false;
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _apiClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = TokenResponse.fromJson(response.data as Map<String, dynamic>);
      await _persistAndActivate(token);
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false);
      if (e.response?.statusCode == 401) {
        throw AuthException('Invalid email or password.');
      }
      if (e.response?.statusCode == 429) {
        throw AuthException('Too many login attempts. Please try again later.');
      }
      throw AuthException('Could not reach the server. Check your connection and try again.');
    }
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      try {
        await _apiClient.dio.post('/auth/logout', data: {'refresh_token': refreshToken});
      } on DioException {
        // Best-effort revoke — proceed with local logout regardless.
      }
    }
    await _forceSignOut();
  }

  Future<void> _persistAndActivate(TokenResponse token) async {
    await _storage.write(key: _accessTokenKey, value: token.accessToken);
    await _storage.write(key: _refreshTokenKey, value: token.refreshToken);
    _apiClient.dio.options.headers['Authorization'] = 'Bearer ${token.accessToken}';
    state = AuthState(user: _decodeUser(token.accessToken), isLoading: false);
  }

  /// Decodes the JWT payload locally (no signature verification — that's
  /// the backend's job) purely to read sub/role/organization_id for the UI.
  AuthenticatedUser _decodeUser(String jwt) {
    final parts = jwt.split('.');
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    return AuthenticatedUser(
      userId: payload['sub'] as String,
      role: payload['role'] as String,
      organizationId: payload['organization_id'] as String?,
    );
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(apiClientProvider), ref.watch(secureStorageProvider)),
);
