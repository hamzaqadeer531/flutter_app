import 'package:dio/dio.dart';

/// Base URL of the FastAPI backend this app talks to exclusively through
/// its documented OpenAPI contracts (Part A: no coupling to backend
/// internals). Overridable at build time: `flutter run --dart-define=API_BASE_URL=...`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000/api/v1',
);

typedef TokenRefresher = Future<String?> Function();

/// Thin Dio wrapper. Token attachment and 401-triggered refresh are wired
/// in by AuthState once a session exists — this class has no auth logic
/// of its own, matching the rest of the codebase's "one thing per module"
/// discipline.
class ApiClient {
  ApiClient()
      : dio = Dio(BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 20),
          // /layout/generate and /parser/parse are synchronous (no job_id
          // + polling, unlike /ocr/process) -- a real multi-page scanned
          // statement can take noticeably longer to lay out/parse than
          // the small digital PDFs this was tuned against. Without a
          // receiveTimeout, a slow response just hangs the UI spinner
          // forever with no error ever surfacing (connectTimeout only
          // covers establishing the TCP connection, not waiting for the
          // response body).
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(minutes: 2),
        ));

  final Dio dio;
}
