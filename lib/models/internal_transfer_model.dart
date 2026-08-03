/// Mirrors backend_python/schemas/internal_transfer.py::InternalTransferWire
/// exactly (HTML feature-parity closure plan, Phase 5).
class InternalTransfer {
  InternalTransfer({
    required this.sourceDocumentId,
    required this.sourceAccount,
    required this.destinationDocumentId,
    required this.destinationAccount,
    required this.dateIso,
    required this.amount,
    required this.referenceNumber,
    required this.confidence,
  });

  final String sourceDocumentId;
  final String sourceAccount;
  final String destinationDocumentId;
  final String destinationAccount;
  final String? dateIso;
  final double amount;
  final String? referenceNumber;
  final String confidence; // 'high' | 'medium' | 'low'

  factory InternalTransfer.fromJson(Map<String, dynamic> json) {
    return InternalTransfer(
      sourceDocumentId: json['source_document_id'] as String,
      sourceAccount: json['source_account'] as String,
      destinationDocumentId: json['destination_document_id'] as String,
      destinationAccount: json['destination_account'] as String,
      dateIso: json['date_iso'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      referenceNumber: json['reference_number'] as String?,
      confidence: json['confidence'] as String? ?? 'low',
    );
  }
}
