/// Mirrors backend_python/schemas/analytics.py::LearningAnalyticsResponse
/// exactly — the only real, already-built analytics data source in the
/// backend today (GET /api/v1/analytics/learning). Several fields are
/// honest proxies rather than ground-truth accuracy (see the backend's
/// own LearningAnalyticsReport docstring) — this model doesn't relabel
/// them as anything stronger.
class LearningAnalytics {
  const LearningAnalytics({
    required this.ocrAccuracyProxy,
    required this.parserAccuracyProxy,
    required this.manualCorrectionRate,
    required this.mostCorrectedFields,
    required this.mostProblematicTemplates,
    required this.templateHitRate,
    required this.averageConfidence,
    required this.correctionsByDay,
  });

  final double ocrAccuracyProxy;
  final double parserAccuracyProxy;
  final double manualCorrectionRate;
  final List<(String, int)> mostCorrectedFields;
  final List<(String, int)> mostProblematicTemplates;
  final double templateHitRate;
  final double averageConfidence;
  final List<(String, int)> correctionsByDay;

  factory LearningAnalytics.fromJson(Map<String, dynamic> json) {
    List<(String, int)> pairs(String key) => (json[key] as List<dynamic>)
        .map((e) => (e[0] as String, (e[1] as num).toInt()))
        .toList();
    return LearningAnalytics(
      ocrAccuracyProxy: (json['ocr_accuracy_proxy'] as num).toDouble(),
      parserAccuracyProxy: (json['parser_accuracy_proxy'] as num).toDouble(),
      manualCorrectionRate: (json['manual_correction_rate'] as num).toDouble(),
      mostCorrectedFields: pairs('most_corrected_fields'),
      mostProblematicTemplates: pairs('most_problematic_templates'),
      templateHitRate: (json['template_hit_rate'] as num).toDouble(),
      averageConfidence: (json['average_confidence'] as num).toDouble(),
      correctionsByDay: pairs('corrections_by_day'),
    );
  }
}
