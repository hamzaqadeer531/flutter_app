/// Mirrors backend_python/schemas/recurring_transaction.py::RecurringTransactionWire
/// exactly (HTML feature-parity closure plan, Phase 6).
class RecurringTransaction {
  RecurringTransaction({
    required this.description,
    required this.type,
    required this.count,
    required this.frequency,
    required this.firstDateIso,
    required this.lastDateIso,
    required this.total,
    required this.average,
  });

  final String description;
  final String type; // 'credit' | 'debit'
  final int count;
  final String frequency; // 'Daily' | 'Weekly' | 'Monthly' | 'Quarterly' | 'Annually' | 'Irregular but recurring'
  final String? firstDateIso;
  final String? lastDateIso;
  final double total;
  final double average;

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    return RecurringTransaction(
      description: json['description'] as String,
      type: json['type'] as String,
      count: json['count'] as int,
      frequency: json['frequency'] as String,
      firstDateIso: json['first_date_iso'] as String?,
      lastDateIso: json['last_date_iso'] as String?,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      average: (json['average'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
