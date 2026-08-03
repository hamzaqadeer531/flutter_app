/// Mirrors backend_python/schemas/insights.py::InsightWire exactly
/// (HTML feature-parity closure plan, Phase 7).
class Insight {
  Insight({required this.type, required this.icon, required this.text});

  final String type; // 'info' | 'warn' | 'alert'
  final String icon;
  final String text;

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      type: json['type'] as String,
      icon: json['icon'] as String,
      text: json['text'] as String,
    );
  }
}
