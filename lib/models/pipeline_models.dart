/// Mirrors backend_python/semantic_parser/contracts.py::Transaction
/// (delivered as a raw dict via ParsedDocumentResponse.parsed_document,
/// per that schema's own documented "pass-through dict" design).
class PipelineTransaction {
  PipelineTransaction({
    required this.dateIso,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.confidence,
    required this.pageNumber,
    required this.sourceCellIds,
    this.referenceNumber,
    this.chequeNumber,
    this.transactionCode,
    this.extractedName,
    this.nameSource,
  });

  String? dateIso;
  String description;
  double? debit;
  double? credit;
  double? balance;
  final double confidence;
  final int pageNumber;

  /// Extracted counterparty name (regex cascade, or the opt-in NER
  /// enhancement pass -- see nameSource) and, when nameSource is 'ner',
  /// which pass produced it. Both null until either GET /transactions/
  /// {id}/reviewed populates them (this model's default source is the
  /// raw parser output, which has neither) or WorkflowController.
  /// enhanceNames() merges a fresh reviewed-transactions fetch in.
  String? extractedName;
  String? nameSource;

  /// The layout cell ids this row was built from -- the SAME identifier
  /// TransactionWire.source_cell_ids documents as the transaction_ref to
  /// pass to every POST /review/{id}/transaction/* endpoint. Previously
  /// silently dropped by this model, which made per-row review actions
  /// (edit/verify/bulk-approve/etc.) impossible to call from the app at
  /// all -- there was no way to identify WHICH transaction a click
  /// referred to once it left the raw JSON response.
  final List<String> sourceCellIds;

  final String? referenceNumber;
  final String? chequeNumber;
  final String? transactionCode;

  factory PipelineTransaction.fromJson(Map<String, dynamic> json) {
    return PipelineTransaction(
      dateIso: json['date_iso'] as String?,
      description: json['description'] as String? ?? '',
      debit: (json['debit'] as num?)?.toDouble(),
      credit: (json['credit'] as num?)?.toDouble(),
      balance: (json['balance'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      pageNumber: (json['page_number'] as num?)?.toInt() ?? 1,
      sourceCellIds: (json['source_cell_ids'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      referenceNumber: json['reference_number'] as String?,
      chequeNumber: json['cheque_number'] as String?,
      transactionCode: json['transaction_code'] as String?,
      extractedName: json['extracted_name'] as String?,
      nameSource: json['name_source'] as String?,
    );
  }

  /// Stable per-row key for anything (edit status maps, list diffing)
  /// that needs to identify "this transaction" without relying on list
  /// index, which shifts under filtering/search in the Review screen.
  String get rowKey => sourceCellIds.join('|');

  /// True for a row a reviewer typed in by hand (WorkflowController.
  /// insertTransaction) rather than one the parser produced -- backend_
  /// python's ReviewService.insert_transaction mints a synthetic
  /// "inserted-`<uuid>`" id as the row's one and only source_cell_ids
  /// entry, since it has no real layout cells behind it. Used to hide
  /// row actions that only make sense against real parsed cells (split
  /// row, merge/split cells, OCR/layout source) and show "retract" in
  /// their place.
  bool get isInserted => sourceCellIds.length == 1 && sourceCellIds.first.startsWith('inserted-');

  PipelineTransaction copyWith({
    String? dateIso,
    String? description,
    double? debit,
    double? credit,
    double? balance,
    String? extractedName,
    String? nameSource,
  }) {
    return PipelineTransaction(
      dateIso: dateIso ?? this.dateIso,
      description: description ?? this.description,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      balance: balance ?? this.balance,
      confidence: confidence,
      pageNumber: pageNumber,
      sourceCellIds: sourceCellIds,
      referenceNumber: referenceNumber,
      chequeNumber: chequeNumber,
      transactionCode: transactionCode,
      extractedName: extractedName ?? this.extractedName,
      nameSource: nameSource ?? this.nameSource,
    );
  }
}

/// Mirrors the top-level shape of semantic_parser.contracts.ParsedDocument
/// as delivered through ParsedDocumentResponse.parsed_document.
class ParsedStatement {
  ParsedStatement({
    required this.transactions,
    required this.openingBalance,
    required this.closingBalance,
    required this.confidence,
    required this.accountTitle,
    required this.accountNumber,
  });

  final List<PipelineTransaction> transactions;
  final double? openingBalance;
  final double? closingBalance;
  final double confidence;
  final String? accountTitle;
  final String? accountNumber;

  factory ParsedStatement.fromJson(Map<String, dynamic> json) {
    final txns = (json['transactions'] as List<dynamic>? ?? [])
        .map((t) => PipelineTransaction.fromJson(t as Map<String, dynamic>))
        .toList();
    final accountInfo = json['account_information'] as Map<String, dynamic>?;
    return ParsedStatement(
      transactions: txns,
      openingBalance: (json['opening_balance'] as num?)?.toDouble(),
      closingBalance: (json['closing_balance'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      accountTitle: accountInfo?['account_title'] as String?,
      accountNumber: accountInfo?['account_number'] as String?,
    );
  }

  ParsedStatement copyWith({List<PipelineTransaction>? transactions}) {
    return ParsedStatement(
      transactions: transactions ?? this.transactions,
      openingBalance: openingBalance,
      closingBalance: closingBalance,
      confidence: confidence,
      accountTitle: accountTitle,
      accountNumber: accountNumber,
    );
  }
}
