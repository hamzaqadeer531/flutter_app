import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

/// One uploaded statement's row in the "Uploaded Statements" queue
/// (HTML feature-parity closure plan, Phase 3) -- mirrors the HTML
/// source's accountStatements entries (Bank/File/Status/Txns/Credits/
/// Debits). Tracked client-side as uploads happen rather than
/// re-fetched from the backend on every change: the backend's
/// WorkingSessionMemberRecord (durable source of truth for which
/// documents belong to this session) only stores document_id/
/// display_order, not this display-friendly summary, and Phase 3's
/// scope is Flutter-only (see the plan) -- no new backend enrichment
/// endpoint for this. Reconstructing this list after an app restart
/// isn't supported yet; a fresh session always starts empty.
class SessionMemberSummary {
  const SessionMemberSummary({
    required this.documentId,
    required this.filename,
    required this.bankHint,
    required this.status,
    this.transactionCount,
    this.totalCredits,
    this.totalDebits,
  });

  final String documentId;
  final String filename;
  final String? bankHint;
  final String status; // WorkflowStage.name -- 'ready', 'failed', etc.
  final int? transactionCount;
  final double? totalCredits;
  final double? totalDebits;
}

/// Working Session (HTML feature-parity closure plan, Phase 2/3) -- the
/// Client Details step's own state plus the Upload step's "Uploaded
/// Statements" queue, mirroring backend_python's WorkingSessionRecord +
/// WorkingSessionMemberRecord. Phase 1's upload flow stamps every
/// uploaded document with an implicit 1-member session and returns its
/// id as DocumentUploadResponse.session_id -- WorkflowController reads
/// that and calls this controller's onDocumentUploaded() so the queue
/// and client-details id both stay in sync with whatever's actually on
/// the backend.
class SessionState {
  const SessionState({
    this.sessionId,
    this.clientName,
    this.ntn,
    this.taxYear,
    this.branch,
    this.preparedDate,
    this.largeTransactionThreshold,
    this.members = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final String? sessionId;
  final String? clientName;
  final String? ntn;
  final String? taxYear;
  final String? branch;
  final String? preparedDate; // ISO 8601 date (YYYY-MM-DD)
  final double? largeTransactionThreshold;
  final List<SessionMemberSummary> members;
  final bool isLoading;
  final String? errorMessage;

  SessionState copyWith({
    String? sessionId,
    String? clientName,
    String? ntn,
    String? taxYear,
    String? branch,
    String? preparedDate,
    double? largeTransactionThreshold,
    List<SessionMemberSummary>? members,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SessionState(
      sessionId: sessionId ?? this.sessionId,
      clientName: clientName ?? this.clientName,
      ntn: ntn ?? this.ntn,
      taxYear: taxYear ?? this.taxYear,
      branch: branch ?? this.branch,
      preparedDate: preparedDate ?? this.preparedDate,
      largeTransactionThreshold: largeTransactionThreshold ?? this.largeTransactionThreshold,
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(const SessionState());

  final Ref _ref;

  /// Called by WorkflowController right after a successful upload.
  /// Phase 1's backend already created (or reused) a session for this
  /// document server-side -- this just mirrors that into local state so
  /// the queue UI and Client Details both see it immediately, with no
  /// extra round trip. A session id switch (a genuinely new session,
  /// not "add another statement to this one") resets the member list;
  /// the normal case -- same sessionId as already tracked, or the very
  /// first upload -- appends.
  void onDocumentUploaded({
    required String sessionId,
    required String documentId,
    required String filename,
    required String? bankHint,
    required String status,
  }) {
    final isNewSession = state.sessionId != null && state.sessionId != sessionId;
    final existingMembers = isNewSession ? const <SessionMemberSummary>[] : state.members;
    state = SessionState(
      sessionId: sessionId,
      clientName: isNewSession ? null : state.clientName,
      ntn: isNewSession ? null : state.ntn,
      taxYear: isNewSession ? null : state.taxYear,
      branch: isNewSession ? null : state.branch,
      preparedDate: isNewSession ? null : state.preparedDate,
      largeTransactionThreshold: isNewSession ? null : state.largeTransactionThreshold,
      members: [
        ...existingMembers.where((m) => m.documentId != documentId),
        SessionMemberSummary(documentId: documentId, filename: filename, bankHint: bankHint, status: status),
      ],
    );
  }

  /// Updates just the status of an already-queued member (e.g. 'ocr' ->
  /// 'ready' once the pipeline finishes, or -> 'failed') without needing
  /// to re-supply filename/bankHint. No-op if this document isn't
  /// tracked (e.g. the session was reset mid-upload).
  void updateMemberStatus(String documentId, String status) {
    state = state.copyWith(
      members: [
        for (final m in state.members)
          if (m.documentId == documentId)
            SessionMemberSummary(
              documentId: m.documentId, filename: m.filename, bankHint: m.bankHint, status: status,
              transactionCount: m.transactionCount, totalCredits: m.totalCredits, totalDebits: m.totalDebits,
            )
          else
            m,
      ],
    );
  }

  /// Removes a statement from the queue -- DELETE /sessions/{id}/
  /// members/{document_id}. The document itself, and everything already
  /// processed for it, is untouched server-side; it just stops being
  /// part of this combined working session.
  Future<bool> removeMember(String documentId) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return false;
    try {
      final dio = _ref.read(apiClientProvider).dio;
      await dio.delete('/sessions/$sessionId/members/$documentId');
      state = state.copyWith(members: state.members.where((m) => m.documentId != documentId).toList());
      return true;
    } catch (error) {
      state = state.copyWith(errorMessage: 'Could not remove statement: $error');
      return false;
    }
  }

  /// Starts a genuinely fresh working session -- "🔄 New Working" (Phase
  /// 8) will call this; also used any time the whole queue should be
  /// cleared without touching what's already been uploaded to the
  /// server (those documents/sessions simply stop being tracked here).
  void reset() => state = const SessionState();

  /// Called once a session id is known (currently: the caller reads it
  /// off DocumentUploadResponse.session_id after a successful upload --
  /// onDocumentUploaded above is the normal path now; this remains for
  /// the Client Details screen to explicitly (re)load a session's
  /// details if it's ever opened without going through Upload first).
  /// Loads whatever client details are already on the session, if any.
  Future<void> setSessionId(String sessionId) async {
    if (state.sessionId == sessionId) return;
    state = SessionState(sessionId: sessionId, isLoading: true);
    try {
      final dio = _ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/$sessionId');
      state = _stateFromSessionResponse(sessionId, response.data as Map<String, dynamic>);
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: 'Could not load session: $error');
    }
  }

  /// Replaces the client-details fields from a fresh server response
  /// (not copyWith's null-coalescing merge) -- a field the server
  /// genuinely returns as null (never set) must actually become null
  /// here, not silently keep whatever stale value was there before.
  /// members is preserved as-is: this endpoint's response only carries
  /// document_id/display_order/added_at per member, not the display
  /// summary (filename/bank/status/etc.) onDocumentUploaded already has.
  SessionState _stateFromSessionResponse(String sessionId, Map<String, dynamic> body) {
    return SessionState(
      sessionId: sessionId,
      clientName: body['client_name'] as String?,
      ntn: body['ntn'] as String?,
      taxYear: body['tax_year'] as String?,
      branch: body['branch'] as String?,
      preparedDate: body['prepared_date'] as String?,
      largeTransactionThreshold: (body['large_transaction_threshold'] as num?)?.toDouble(),
      members: state.sessionId == sessionId ? state.members : const [],
      isLoading: false,
    );
  }

  Future<bool> updateClientDetails({
    String? clientName,
    String? ntn,
    String? taxYear,
    String? branch,
    String? preparedDate,
    double? largeTransactionThreshold,
  }) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final dio = _ref.read(apiClientProvider).dio;
      final requestBody = <String, dynamic>{};
      if (clientName != null) requestBody['client_name'] = clientName;
      if (ntn != null) requestBody['ntn'] = ntn;
      if (taxYear != null) requestBody['tax_year'] = taxYear;
      if (branch != null) requestBody['branch'] = branch;
      if (preparedDate != null) requestBody['prepared_date'] = preparedDate;
      if (largeTransactionThreshold != null) requestBody['large_transaction_threshold'] = largeTransactionThreshold;
      final response = await dio.patch('/sessions/$sessionId/client-details', data: requestBody);
      state = _stateFromSessionResponse(sessionId, response.data as Map<String, dynamic>);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: 'Could not save client details: $error');
      return false;
    }
  }
}

final sessionControllerProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref),
);
