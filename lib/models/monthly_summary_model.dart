/// Mirrors backend_python/schemas/monthly_summary.py::MonthlySummaryWire
/// exactly (Analytics Dashboard follow-up, HTML feature-parity closure
/// Phase 7 scope).
class MonthlySummary {
  MonthlySummary({required this.month, required this.totalCredits, required this.totalDebits, required this.net});

  final String month; // "YYYY-MM"
  final double totalCredits;
  final double totalDebits;
  final double net;

  factory MonthlySummary.fromJson(Map<String, dynamic> json) {
    return MonthlySummary(
      month: json['month'] as String,
      totalCredits: (json['total_credits'] as num?)?.toDouble() ?? 0.0,
      totalDebits: (json['total_debits'] as num?)?.toDouble() ?? 0.0,
      net: (json['net'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
