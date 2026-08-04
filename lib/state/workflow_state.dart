import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pipeline_models.dart';
import 'auth_state.dart';
import 'session_state.dart';

enum WorkflowStage { idle, uploading, ocr, layout, parsing, ready, failed }

class WorkflowState {
  const WorkflowState({
    this.stage = WorkflowStage.idle,
    this.documentId,
    this.documentTypeId,
    this.filename,
    this.bank,
    this.progressMessage,
    this.errorMessage,
    this.statement,
    this.nameEnhancementNote,
  });

  final WorkflowStage stage;
  final String? documentId;

  /// Populated from DocumentUploadResponse.document_type_id -- null when
  /// the document couldn't be auto-classified. Required by POST
  /// /review/{id}/verify's request body, so verifyDocument() below can't
  /// run without it.
  final String? documentTypeId;
  final String? filename;
  final String? bank;
  final String? progressMessage;
  final String? errorMessage;
  final ParsedStatement? statement;

  /// Soft, non-blocking status for the automatic post-upload NER name
  /// enhancement pass (see _autoEnhanceNames below) -- deliberately kept
  /// separate from errorMessage, since a failed background enhancement
  /// (e.g. the bundled model isn't staged) must never look like the
  /// whole upload failed. Null once cleared or on the next upload.
  final String? nameEnhancementNote;

  bool get isBusy => stage == WorkflowStage.uploading || stage == WorkflowStage.ocr || stage == WorkflowStage.layout || stage == WorkflowStage.parsing;

  WorkflowState copyWith({
    WorkflowStage? stage,
    String? documentId,
    String? documentTypeId,
    String? filename,
    String? bank,
    String? progressMessage,
    String? errorMessage,
    ParsedStatement? statement,
    String? nameEnhancementNote,
    bool clearNameEnhancementNote = false,
  }) {
    return WorkflowState(
      stage: stage ?? this.stage,
      documentId: documentId ?? this.documentId,
      documentTypeId: documentTypeId ?? this.documentTypeId,
      filename: filename ?? this.filename,
      bank: bank ?? this.bank,
      progressMessage: progressMessage,
      errorMessage: errorMessage,
      statement: statement ?? this.statement,
      nameEnhancementNote: clearNameEnhancementNote ? null : (nameEnhancementNote ?? this.nameEnhancementNote),
    );
  }
}

/// Drives the real Upload -> OCR -> Layout -> Parse pipeline
/// (POST /documents/upload -> POST /ocr/process -> poll GET
/// /ocr/status/{job_id} -> POST /layout/generate/{id} -> POST
/// /parser/parse/{id}), matching the HTML source's Step 1 "parseProgress"
/// UI (spinner + progress bar + status message) which lives inline in the
/// Upload screen rather than as its own separate step.
class WorkflowController extends StateNotifier<WorkflowState> {
  WorkflowController(this._ref) : super(const WorkflowState());

  final Ref _ref;

  /// filePath is used on desktop/mobile; fileBytes is required on web,
  /// where browsers never expose a real filesystem path for a picked file
  /// (file_picker's PlatformFile.path is always null there) -- exactly one
  /// of the two must be supplied.
  Future<void> uploadAndProcess({
    String? filePath,
    Uint8List? fileBytes,
    required String filename,
    required String? bank,
    String? ocrEngine,
  }) async {
    assert(filePath != null || fileBytes != null, 'Must supply either filePath or fileBytes.');
    final dio = _ref.read(apiClientProvider).dio;
    state = WorkflowState(stage: WorkflowStage.uploading, filename: filename, bank: bank, progressMessage: 'Uploading statement...');

    try {
      final multipartFile = filePath != null
          ? await MultipartFile.fromFile(filePath, filename: filename)
          : MultipartFile.fromBytes(fileBytes!, filename: filename);
      final formData = FormData.fromMap({
        'file': multipartFile,
        if (bank != null) 'bank_hint': bank, // ignore: use_null_aware_elements
      });
      final uploadResponse = await dio.post('/documents/upload', data: formData);
      final documentId = uploadResponse.data['document_id'] as String;
      final documentTypeId = uploadResponse.data['document_type_id'] as String?;
      final sessionId = uploadResponse.data['session_id'] as String?;
      state = state.copyWith(
        documentId: documentId,
        documentTypeId: documentTypeId,
        stage: WorkflowStage.ocr,
        progressMessage: 'Reading document (OCR)...',
      );
      // HTML feature-parity closure Phase 3 -- Phase 1's backend already
      // stamped this upload with a (possibly brand new) Working Session;
      // mirror that into the queue/Client Details state immediately,
      // rather than waiting for the whole OCR/layout/parse pipeline to
      // finish, so a failure partway through still leaves the statement
      // visibly queued (status reflects the current stage below).
      if (sessionId != null) {
        _ref.read(sessionControllerProvider.notifier).onDocumentUploaded(
              sessionId: sessionId,
              documentId: documentId,
              filename: filename,
              bankHint: bank,
              status: WorkflowStage.ocr.name,
            );
      }
      await _runOcrLayoutParse(dio, documentId, ocrEngine: ocrEngine, forceReprocess: false);
      _ref.read(sessionControllerProvider.notifier).updateMemberStatus(documentId, WorkflowStage.ready.name);
    } catch (error) {
      final message = error is DioException && error.response?.statusCode == 401
          ? 'Your session just refreshed — please try uploading again.'
          : error.toString();
      state = state.copyWith(stage: WorkflowStage.failed, errorMessage: message);
      if (state.documentId != null) {
        _ref.read(sessionControllerProvider.notifier).updateMemberStatus(state.documentId!, WorkflowStage.failed.name);
      }
    }
  }

  /// Re-runs OCR -> Layout -> Parse on the ALREADY-uploaded document with a
  /// different engine — the realistic "this bank's statement didn't parse
  /// well, try the other reader" workflow, without re-uploading the file.
  Future<void> reprocessWithEngine(String ocrEngine) async {
    final documentId = state.documentId;
    if (documentId == null) return;
    final dio = _ref.read(apiClientProvider).dio;
    state = state.copyWith(
      stage: WorkflowStage.ocr,
      progressMessage: 'Re-reading document with a different OCR engine...',
    );
    try {
      await _runOcrLayoutParse(dio, documentId, ocrEngine: ocrEngine, forceReprocess: true);
    } catch (error) {
      state = state.copyWith(stage: WorkflowStage.failed, errorMessage: error.toString());
    }
  }

  Future<void> _runOcrLayoutParse(
    Dio dio,
    String documentId, {
    required String? ocrEngine,
    required bool forceReprocess,
  }) async {
    final ocrBody = <String, dynamic>{'document_id': documentId, 'force_reprocess': forceReprocess};
    if (ocrEngine != null) ocrBody['engine'] = ocrEngine;
    final ocrProcessResponse = await dio.post('/ocr/process', data: ocrBody);
    final jobId = ocrProcessResponse.data['job_id'] as String;
    await _pollOcrJob(dio, jobId);

    state = state.copyWith(stage: WorkflowStage.layout, progressMessage: 'Analyzing table layout...');
    await dio.post('/layout/generate/$documentId');

    state = state.copyWith(stage: WorkflowStage.parsing, progressMessage: 'Extracting transactions...');
    final parseResponse = await dio.post('/parser/parse/$documentId');
    final statement = ParsedStatement.fromJson(parseResponse.data['parsed_document'] as Map<String, dynamic>);

    state = state.copyWith(stage: WorkflowStage.ready, statement: statement, progressMessage: null, clearNameEnhancementNote: true);

    // HTML feature-parity: try NER-assisted name enhancement automatically
    // right after every parse, instead of requiring the manual "Enhance
    // Names (AI)" button click every time. Best-effort only -- this must
    // never fail the upload itself; enhanceNames() already only fills
    // gaps the always-on regex cascade left blank, so skipping it here
    // just means those rows stay exactly as they already were.
    try {
      await enhanceNames();
    } catch (error) {
      state = state.copyWith(
        nameEnhancementNote: 'Automatic name enhancement was skipped: $error',
      );
    }
  }

  /// Terminal job states the backend's JobManager can report (see
  /// jobs/job_manager.py::JobStatus) -- every one of these means the job
  /// has definitely finished and polling must stop. Previously only
  /// "succeeded"/"failed" were recognized: a real (large/scanned)
  /// statement whose OCR exceeds the backend's own 120s per-job timeout
  /// comes back as "timed_out", which fell through unrecognized and left
  /// this loop polling forever with the spinner showing -- indistinguishable
  /// from the app being stuck, since no error was ever thrown to display.
  static const _terminalFailureStates = {'failed', 'cancelled', 'timed_out'};

  /// Overall wall-clock cap independent of any single request's timeout --
  /// guards against a job that (for whatever reason) never reaches a
  /// terminal state at all, so this loop still surfaces a clear error
  /// instead of polling indefinitely.
  static const _maxPollDuration = Duration(minutes: 5);

  Future<void> _pollOcrJob(Dio dio, String jobId) async {
    final deadline = DateTime.now().add(_maxPollDuration);
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw Exception('OCR is taking longer than expected (5+ minutes). Please try again or use a different OCR engine.');
      }
      await Future.delayed(const Duration(milliseconds: 800));
      final response = await dio.get('/ocr/status/$jobId');
      final status = response.data['status'] as String;
      if (status == 'succeeded') return;
      if (_terminalFailureStates.contains(status)) {
        throw Exception(response.data['error_message'] ?? 'OCR job did not complete (status: $status).');
      }
    }
  }

  /// Corrects one field of one transaction via POST /review/{id}/
  /// transaction/edit -- the actual backend endpoint the Review screen's
  /// own subtitle ("Correct debit/credit, amounts, or descriptions
  /// inline") promises but, until now, never called. fieldName must be
  /// one of the backend's supported transaction fields (review_service.py
  /// ::ReviewService.edit_transaction / edit_transaction_category /
  /// edit_transaction_name): category, extracted_name, date_iso,
  /// description, debit, credit, balance.
  ///
  /// On success, updates the in-memory statement so the UI reflects the
  /// correction immediately without a full re-fetch -- matches what a
  /// GET /transactions/{id}/reviewed call would show, since that
  /// endpoint overlays the exact same annotation this call just wrote
  /// (services/transaction_intelligence_service.py::apply_transaction_corrections).
  /// Throws on failure; the caller (Review screen) is responsible for
  /// catching and showing per-cell error feedback -- this method doesn't
  /// touch WorkflowState.errorMessage, since a single cell's failed edit
  /// isn't a whole-workflow failure.
  Future<void> editTransactionField({
    required PipelineTransaction transaction,
    required String fieldName,
    required String? originalValue,
    required String correctedValue,
  }) async {
    final documentId = state.documentId;
    final statement = state.statement;
    if (documentId == null || statement == null) {
      throw StateError('No active document to edit a transaction on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post(
      '/review/$documentId/transaction/edit',
      data: {
        'page_number': transaction.pageNumber,
        'transaction_ref': transaction.sourceCellIds,
        'field_name': fieldName,
        'original_value': originalValue,
        'corrected_value': correctedValue,
      },
    );

    final updatedTransactions = statement.transactions.map((t) {
      if (t.rowKey != transaction.rowKey) return t;
      switch (fieldName) {
        case 'date_iso':
          return t.copyWith(dateIso: correctedValue);
        case 'description':
          return t.copyWith(description: correctedValue);
        case 'debit':
          return t.copyWith(debit: double.parse(correctedValue.replaceAll(',', '')));
        case 'credit':
          return t.copyWith(credit: double.parse(correctedValue.replaceAll(',', '')));
        case 'balance':
          return t.copyWith(balance: double.parse(correctedValue.replaceAll(',', '')));
        default:
          return t;
      }
    }).toList();
    state = state.copyWith(statement: statement.copyWith(transactions: updatedTransactions));
  }

  /// Flags one transaction row as having an OCR, parser, or
  /// classification problem -- POST /review/{id}/mark-{kind}-error.
  /// Doesn't touch WorkflowState.statement: this records an annotation
  /// for the review/correction-learning trail, it doesn't change any
  /// field's value (unlike editTransactionField above).
  Future<void> markTransactionError({
    required PipelineTransaction transaction,
    required String errorKind, // 'ocr' | 'parser' | 'classification'
    String? note,
  }) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to flag a transaction on.');
    }
    final endpoint = switch (errorKind) {
      'ocr' => 'mark-ocr-error',
      'parser' => 'mark-parser-error',
      'classification' => 'mark-classification-error',
      _ => throw ArgumentError('Unknown errorKind: $errorKind'),
    };
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post(
      '/review/$documentId/$endpoint',
      data: {
        'page_number': transaction.pageNumber,
        'target_type': 'transaction_row',
        'target_ref': transaction.sourceCellIds,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  /// Groups by pageNumber since the backend's bulk endpoints take a single
  /// page_number per request -- a selection spanning multiple pages of a
  /// real statement needs one call per page.
  Map<int, List<PipelineTransaction>> _groupByPage(List<PipelineTransaction> transactions) {
    final byPage = <int, List<PipelineTransaction>>{};
    for (final t in transactions) {
      byPage.putIfAbsent(t.pageNumber, () => []).add(t);
    }
    return byPage;
  }

  /// Approves a batch of transactions at once -- POST /review/{id}/
  /// transaction/bulk-approve -- confirming their classifications stand
  /// without touching any field value. Backend gates this to reviewer/
  /// admin roles (services/review_service.py via require_role), so the
  /// Review screen only shows the bulk actions to those roles.
  Future<void> bulkApproveTransactions(List<PipelineTransaction> transactions) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to bulk-approve transactions on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    for (final entry in _groupByPage(transactions).entries) {
      await dio.post(
        '/review/$documentId/transaction/bulk-approve',
        data: {
          'page_number': entry.key,
          'transaction_refs': entry.value.map((t) => t.sourceCellIds).toList(),
        },
      );
    }
  }

  /// Rejects a batch of transactions at once -- POST /review/{id}/
  /// transaction/bulk-reject -- same reviewer/admin gate as bulk-approve.
  Future<void> bulkRejectTransactions(List<PipelineTransaction> transactions, {String? note}) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to bulk-reject transactions on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    for (final entry in _groupByPage(transactions).entries) {
      await dio.post(
        '/review/$documentId/transaction/bulk-reject',
        data: {
          'page_number': entry.key,
          'transaction_refs': entry.value.map((t) => t.sourceCellIds).toList(),
          if (note != null && note.isNotEmpty) 'note': note, // ignore: use_null_aware_elements
        },
      );
    }
  }

  /// Merges several transaction rows into one -- POST /review/{id}/
  /// merge-rows. Unlike bulk-approve/reject, merge/split-rows/cells have
  /// no role gate on the backend (get_current_user, not require_role),
  /// so this is reachable by any authenticated user, not just reviewer/
  /// admin. Each transaction's sourceCellIds IS the row_ref the backend
  /// expects, since that's exactly the cell-id list a parsed row was
  /// built from. Records an annotation only -- like markTransactionError,
  /// it doesn't attempt to locally re-derive the merged row's fields,
  /// since that requires re-running the parser; the merge takes effect
  /// on the next reprocess.
  Future<void> mergeRows(List<PipelineTransaction> transactions) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to merge rows on.');
    }
    if (transactions.length < 2) {
      throw ArgumentError('Select at least two rows to merge.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    for (final entry in _groupByPage(transactions).entries) {
      if (entry.value.length < 2) continue; // nothing to merge on this page alone
      await dio.post(
        '/review/$documentId/merge-rows',
        data: {
          'page_number': entry.key,
          'row_refs': entry.value.map((t) => t.sourceCellIds).toList(),
        },
      );
    }
  }

  /// Splits one transaction row's cells into multiple resulting rows --
  /// POST /review/{id}/split-rows. resultingRefs is the caller-supplied
  /// grouping of transaction.sourceCellIds into 2+ new row_refs.
  Future<void> splitRows(PipelineTransaction transaction, List<List<String>> resultingRefs) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to split a row on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post(
      '/review/$documentId/split-rows',
      data: {
        'page_number': transaction.pageNumber,
        'row_ref': transaction.sourceCellIds,
        'resulting_refs': resultingRefs,
      },
    );
  }

  /// Merges several individual cells within a row into one -- POST
  /// /review/{id}/merge-cells.
  Future<void> mergeCells(PipelineTransaction transaction, List<String> cellRefs) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to merge cells on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post(
      '/review/$documentId/merge-cells',
      data: {'page_number': transaction.pageNumber, 'cell_refs': cellRefs},
    );
  }

  /// Splits one cell's text into several resulting cells -- POST
  /// /review/{id}/split-cells.
  Future<void> splitCells(PipelineTransaction transaction, String cellRef, List<String> resultingTexts) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to split a cell on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post(
      '/review/$documentId/split-cells',
      data: {'page_number': transaction.pageNumber, 'cell_ref': cellRef, 'resulting_texts': resultingTexts},
    );
  }

  /// Marks the document verified -- POST /review/{id}/verify -- which
  /// kicks off backend template learning as a background job. Requires
  /// documentTypeId, which only became reliably non-null once the backend
  /// started seeding a DocumentType row per plugin at startup and
  /// resolving it on upload; before that this endpoint had no valid
  /// document_type_id any client could ever supply. Reuses _pollOcrJob
  /// since the job registry (and its status/error shape) is shared
  /// across every background job, not OCR-specific.
  Future<void> verifyDocument() async {
    final documentId = state.documentId;
    final documentTypeId = state.documentTypeId;
    if (documentId == null || documentTypeId == null) {
      throw StateError('This document has no confirmed type to verify.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    final response = await dio.post(
      '/review/$documentId/verify',
      data: {'document_type_id': documentTypeId},
    );
    final jobId = response.data['job_id'] as String;
    await _pollOcrJob(dio, jobId);
  }

  /// Explicit, opt-in NER-assisted second name-extraction pass -- POST
  /// /review/{id}/enhance-names -- for transactions the always-on regex
  /// cascade found nothing for (services/review_service.py::
  /// enhance_names_with_ner). Runs as a background job on the server (a
  /// CPU model load + inference pass isn't fast enough to block the
  /// request), so this reuses _pollOcrJob exactly like verifyDocument
  /// does. Once the job succeeds, re-fetches GET /transactions/{id}/
  /// reviewed and merges each row's extracted_name/name_source in by
  /// sourceCellIds -- merged, not replaced wholesale, so any locally-
  /// tracked date/description/debit/credit/balance edits from
  /// editTransactionField survive.
  Future<void> enhanceNames() async {
    final documentId = state.documentId;
    final statement = state.statement;
    if (documentId == null || statement == null) {
      throw StateError('No active document to enhance names on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    final response = await dio.post('/review/$documentId/enhance-names');
    final jobId = response.data['job_id'] as String;
    await _pollOcrJob(dio, jobId);

    final reviewedResponse = await dio.get('/transactions/$documentId/reviewed');
    final reviewedRows = (reviewedResponse.data as List<dynamic>).cast<Map<String, dynamic>>();
    final rowByKey = {
      for (final row in reviewedRows)
        (row['source_cell_ids'] as List<dynamic>? ?? []).cast<String>().join('|'): row,
    };

    final updatedTransactions = statement.transactions.map((t) {
      final row = rowByKey[t.rowKey];
      if (row == null) return t;
      return t.copyWith(extractedName: row['extracted_name'] as String?, nameSource: row['name_source'] as String?);
    }).toList();
    state = state.copyWith(statement: statement.copyWith(transactions: updatedTransactions));
  }

  /// Balance gaps between existing transactions -- GET /review/{id}/
  /// missing-transaction-candidates (classification.
  /// missing_transaction_detection). Stateless on the server, so this is
  /// safe to call again after an insert/retract to see the list update;
  /// nothing here is cached client-side.
  Future<List<Map<String, dynamic>>> fetchMissingTransactionCandidates() async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to check for missing transactions.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    final response = await dio.get('/review/$documentId/missing-transaction-candidates');
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Adds a transaction the parser missed entirely -- POST /review/{id}/
  /// transaction/insert -- typically to fill a gap
  /// fetchMissingTransactionCandidates() surfaced, but works standalone
  /// too. Unlike editTransactionField (which patches one row by key),
  /// this changes the row COUNT, so the statement is refreshed wholesale
  /// from GET /transactions/{id}/reviewed afterward rather than merged.
  Future<void> insertTransaction({
    String? dateIso,
    required String description,
    double? debit,
    double? credit,
    double? balance,
    String? category,
    String? extractedName,
  }) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to insert a transaction into.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post('/review/$documentId/transaction/insert', data: {
      'date_iso': dateIso,
      'description': description,
      'debit': debit,
      'credit': credit,
      'balance': balance,
      'category': category,
      'extracted_name': extractedName,
    });
    await _refreshReviewedTransactions();
  }

  /// Undoes a wrongly-inserted transaction -- POST /review/{id}/
  /// transaction/retract-insert. transactionRef is the target_ref
  /// insertTransaction's own ReviewActionResponse returned (a synthetic
  /// "inserted-`<uuid>`" id, not real source_cell_ids).
  Future<void> retractInsertedTransaction(List<String> transactionRef) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to retract a transaction from.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post('/review/$documentId/transaction/retract-insert', data: {'transaction_ref': transactionRef});
    await _refreshReviewedTransactions();
  }

  /// AI Validation (Gemini Stage 1) -- POST /review/{id}/validate. Sends
  /// the ORIGINAL uploaded file to Gemini for an independent cross-check
  /// against the local parse; read-only and stateless on the server, so
  /// this can be called again freely (e.g. after applying a correction,
  /// to see the list shrink). Returns the raw response map (overall_
  /// confidence/summary/warnings/corrections) for the Review screen to
  /// render directly -- no dedicated model, same as
  /// fetchMissingTransactionCandidates().
  Future<Map<String, dynamic>> validateWithAI() async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to validate.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    final response = await dio.post('/review/$documentId/validate');
    return response.data as Map<String, dynamic>;
  }

  /// Local parser validation (semantic_parser/balance_validator.py) --
  /// POST /parser/validate/{id}. Re-runs the SAME deterministic balance/
  /// duplicate checks the Verify screen's reconciliation already relies
  /// on, no Gemini call involved. HTML feature-parity closure Phase 12
  /// folds these warning codes into the AI Validation dialog's
  /// categorized report alongside Gemini's corrections, rather than
  /// treating them as a separate feature.
  Future<List<Map<String, dynamic>>> fetchParserValidationWarnings() async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to validate.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    final response = await dio.post('/parser/validate/$documentId');
    return (response.data['warnings'] as List).cast<Map<String, dynamic>>();
  }

  /// AI Auto-Repair (Gemini Stage 3) -- POST /review/{id}/transaction/
  /// apply-ai-correction. Not a new mutation path server-side (see
  /// ReviewService.apply_ai_correction) -- refreshes the statement
  /// wholesale afterward, same reasoning as insertTransaction: a "type"
  /// correction touches two fields (debit AND credit) at once, which a
  /// single-row merge-by-key wouldn't safely express.
  Future<void> applyAICorrection({
    required List<String> transactionRef,
    required String kind,
    required Object suggestedValue,
  }) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to apply a correction to.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post('/review/$documentId/transaction/apply-ai-correction', data: {
      'transaction_ref': transactionRef,
      'kind': kind,
      'suggested_value': suggestedValue,
    });
    await _refreshReviewedTransactions();
  }

  /// AI Recovery (Gemini Stage 2) -- POST /review/{id}/recover. A full,
  /// fresh re-extraction of the ORIGINAL file, for when the local parse
  /// looks bad enough a reviewer wants an independent second attempt.
  /// Staged: returns candidate transactions but changes nothing --
  /// acceptAIRecovery below is the only thing that actually replaces
  /// the document's data, and only once a reviewer explicitly confirms.
  Future<Map<String, dynamic>> recoverWithAI() async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to run AI Recovery on.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    final response = await dio.post('/review/$documentId/recover');
    return response.data as Map<String, dynamic>;
  }

  /// Replaces the ENTIRE transaction list with the accepted recovery
  /// candidates -- POST /review/{id}/recover/accept -- then refreshes
  /// wholesale from GET /transactions/{id}/reviewed, same as
  /// insertTransaction/applyAICorrection. transactions is the exact
  /// list recoverWithAI() returned (a reviewer may have removed
  /// obviously-wrong rows from it first).
  Future<void> acceptAIRecovery(List<Map<String, dynamic>> transactions) async {
    final documentId = state.documentId;
    if (documentId == null) {
      throw StateError('No active document to accept AI Recovery for.');
    }
    final dio = _ref.read(apiClientProvider).dio;
    await dio.post('/review/$documentId/recover/accept', data: {'transactions': transactions});
    await _refreshReviewedTransactions();
  }

  Future<void> _refreshReviewedTransactions() async {
    final documentId = state.documentId;
    final statement = state.statement;
    if (documentId == null || statement == null) return;
    final dio = _ref.read(apiClientProvider).dio;
    final response = await dio.get('/transactions/$documentId/reviewed');
    final rows = (response.data as List<dynamic>).cast<Map<String, dynamic>>();
    final transactions = rows.map((r) => PipelineTransaction.fromJson(r)).toList();
    state = state.copyWith(statement: statement.copyWith(transactions: transactions));
  }

  void reset() => state = const WorkflowState();
}

final workflowControllerProvider = StateNotifierProvider<WorkflowController, WorkflowState>(
  (ref) => WorkflowController(ref),
);
