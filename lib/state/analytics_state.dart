import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics_models.dart';
import 'auth_state.dart';

/// Fetches GET /api/v1/analytics/learning once per Dashboard visit.
/// `autoDispose` so a stale report isn't shown if the user signs out and
/// back in as someone else.
final learningAnalyticsProvider = FutureProvider.autoDispose<LearningAnalytics>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get('/analytics/learning');
  return LearningAnalytics.fromJson(response.data as Map<String, dynamic>);
});
