/// Mirrors backend_python/schemas/verification.py exactly (HTML
/// feature-parity closure plan, Phase 4) -- the Verify & Check step's
/// GET /sessions/{id}/verification response.
class BankSummary {
  BankSummary({
    required this.bankName,
    required this.accountTitle,
    required this.accountNumber,
    required this.currency,
    required this.statementPeriodStart,
    required this.statementPeriodEnd,
    required this.openingBalance,
    required this.closingBalance,
    required this.totalCredits,
    required this.totalDebits,
    required this.netMovement,
    required this.creditCount,
    required this.debitCount,
    required this.extractionConfidence,
    required this.processedDate,
  });

  final String? bankName;
  final String? accountTitle;
  final String? accountNumber;
  final String? currency;
  final String? statementPeriodStart;
  final String? statementPeriodEnd;
  final double? openingBalance;
  final double? closingBalance;
  final double totalCredits;
  final double totalDebits;
  final double netMovement;
  final int creditCount;
  final int debitCount;
  final double extractionConfidence;
  final String processedDate;

  factory BankSummary.fromJson(Map<String, dynamic> json) {
    return BankSummary(
      bankName: json['bank_name'] as String?,
      accountTitle: json['account_title'] as String?,
      accountNumber: json['account_number'] as String?,
      currency: json['currency'] as String?,
      statementPeriodStart: json['statement_period_start'] as String?,
      statementPeriodEnd: json['statement_period_end'] as String?,
      openingBalance: (json['opening_balance'] as num?)?.toDouble(),
      closingBalance: (json['closing_balance'] as num?)?.toDouble(),
      totalCredits: (json['total_credits'] as num?)?.toDouble() ?? 0.0,
      totalDebits: (json['total_debits'] as num?)?.toDouble() ?? 0.0,
      netMovement: (json['net_movement'] as num?)?.toDouble() ?? 0.0,
      creditCount: (json['credit_count'] as num?)?.toInt() ?? 0,
      debitCount: (json['debit_count'] as num?)?.toInt() ?? 0,
      extractionConfidence: (json['extraction_confidence'] as num?)?.toDouble() ?? 0.0,
      processedDate: json['processed_date'] as String? ?? '',
    );
  }
}

class VerificationWarning {
  VerificationWarning({required this.code, required this.message, this.pageNumber});

  final String code;
  final String message;
  final int? pageNumber;

  factory VerificationWarning.fromJson(Map<String, dynamic> json) {
    return VerificationWarning(
      code: json['code'] as String,
      message: json['message'] as String,
      pageNumber: (json['page_number'] as num?)?.toInt(),
    );
  }
}

class SummaryGroup {
  SummaryGroup({required this.category, required this.name, required this.count, required this.total});

  final String? category;
  final String? name;
  final int count;
  final double total;

  factory SummaryGroup.fromJson(Map<String, dynamic> json) {
    return SummaryGroup(
      category: json['category'] as String?,
      name: json['name'] as String?,
      count: (json['count'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AccountVerification {
  AccountVerification({
    required this.documentId,
    required this.filename,
    required this.reconciled,
    required this.warnings,
    required this.bankSummary,
    required this.creditSummary,
    required this.debitSummary,
  });

  final String documentId;
  final String filename;
  final bool reconciled;
  final List<VerificationWarning> warnings;
  final BankSummary bankSummary;
  final List<SummaryGroup> creditSummary;
  final List<SummaryGroup> debitSummary;

  factory AccountVerification.fromJson(Map<String, dynamic> json) {
    return AccountVerification(
      documentId: json['document_id'] as String,
      filename: json['filename'] as String,
      reconciled: json['reconciled'] as bool? ?? false,
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((w) => VerificationWarning.fromJson(w as Map<String, dynamic>))
          .toList(),
      bankSummary: BankSummary.fromJson(json['bank_summary'] as Map<String, dynamic>),
      creditSummary: (json['credit_summary'] as List<dynamic>? ?? [])
          .map((g) => SummaryGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
      debitSummary: (json['debit_summary'] as List<dynamic>? ?? [])
          .map((g) => SummaryGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ExportReadinessItem {
  ExportReadinessItem({required this.label, required this.ok});

  final String label;
  final bool ok;

  factory ExportReadinessItem.fromJson(Map<String, dynamic> json) {
    return ExportReadinessItem(label: json['label'] as String, ok: json['ok'] as bool? ?? false);
  }
}

class SessionVerification {
  SessionVerification({required this.accounts, required this.exportReady, required this.checklist});

  final List<AccountVerification> accounts;
  final bool exportReady;
  final List<ExportReadinessItem> checklist;

  factory SessionVerification.fromJson(Map<String, dynamic> json) {
    return SessionVerification(
      accounts: (json['accounts'] as List<dynamic>? ?? [])
          .map((a) => AccountVerification.fromJson(a as Map<String, dynamic>))
          .toList(),
      exportReady: json['export_ready'] as bool? ?? false,
      checklist: (json['export_readiness_checklist'] as List<dynamic>? ?? [])
          .map((c) => ExportReadinessItem.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
