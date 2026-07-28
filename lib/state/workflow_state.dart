import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pipeline_models.dart';
import 'auth_state.dart';

enum WorkflowStage { idle, uploading, ocr, layout, parsing, ready, failed }

class WorkflowState {
  const WorkflowState({
    this.stage = WorkflowStage.idle,
    this.documentId,
    this.filename,
    this.bank,
    this.progressMessage,
    this.errorMessage,
    this.statement,
  });

  final WorkflowStage stage;
  final String? documentId;
  final String? filename;
  final String? bank;
  final String? progressMessage;
  final String? errorMessage;
  final ParsedStatement? statement;

  bool get isBusy => stage == WorkflowStage.uploading || stage == WorkflowStage.ocr || stage == WorkflowStage.layout || stage == WorkflowStage.parsing;

  WorkflowState copyWith({
    WorkflowStage? stage,
    String? documentId,
    String? filename,
    String? bank,
    String? progressMessage,
    String? errorMessage,
    ParsedStatement? statement,
  }) {
    return WorkflowState(
      stage: stage ?? this.stage,
      documentId: documentId ?? this.documentId,
      filename: filename ?? this.filename,
      bank: bank ?? this.bank,
      progressMessage: progressMessage,
      errorMessage: errorMessage,
      statement: statement ?? this.statement,
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

  Future<void> uploadAndProcess({
    required String filePath,
    required String filename,
    required String? bank,
    String? ocrEngine,
  }) async {
    final dio = _ref.read(apiClientProvider).dio;
    state = WorkflowState(stage: WorkflowStage.uploading, filename: filename, bank: bank, progressMessage: 'Uploading statement...');

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: filename),
        if (bank != null) 'bank_hint': bank,
      });
      final uploadResponse = await dio.post('/documents/upload', data: formData);
      final documentId = uploadResponse.data['document_id'] as String;
      state = state.copyWith(documentId: documentId, stage: WorkflowStage.ocr, progressMessage: 'Reading document (OCR)...');
      await _runOcrLayoutParse(dio, documentId, ocrEngine: ocrEngine, forceReprocess: false);
    } catch (error) {
      state = state.copyWith(stage: WorkflowStage.failed, errorMessage: error.toString());
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

    state = state.copyWith(stage: WorkflowStage.ready, statement: statement, progressMessage: null);
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

  void reset() => state = const WorkflowState();
}

final workflowControllerProvider = StateNotifierProvider<WorkflowController, WorkflowState>(
  (ref) => WorkflowController(ref),
);
