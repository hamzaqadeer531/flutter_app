import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/monthly_summary_model.dart';
import '../../state/auth_state.dart';
import '../../state/session_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/wizard_steps.dart';

/// Client Details (HTML feature-parity closure plan, Phase 2; brought to
/// full parity with the HTML source's Step 2 in this pass). Matches the
/// HTML's Step 2 fields (Client Name, NTN, Tax Year, Branch, Prepared
/// Date, Large Transaction Threshold) plus the three behaviors that
/// were still missing:
///   1. Client Name/Branch auto-filled from the statement's own
///      extracted account title/branch, same as the HTML's own
///      `if(!cnField.value.trim() && primary.client) cnField.value=...`
///      guard -- only fills an EMPTY field, never overwrites a manual edit.
///   2. A live "N of M transactions fall within this tax year" hint when
///      a tax year is selected, from GET /sessions/{id}/monthly-summary.
///      (Scoped to the hint only -- unlike the HTML source, this does not
///      also filter what Review/Verify/Analytics/Export show; that's a
///      materially larger cross-cutting change left for a follow-up.)
///   3. WizardSteps + an explicit "Next: Review Transactions →" button,
///      matching every other step's btn-row -- previously this screen had
///      neither, so the only way off it was the step-tab bar itself.
const List<String> taxYearOptions = [
  'TY 2026 (Jul 2025 – Jun 2026)',
  'TY 2025 (Jul 2024 – Jun 2025)',
  'TY 2024 (Jul 2023 – Jun 2024)',
  'TY 2023 (Jul 2022 – Jun 2023)',
  'TY 2022 (Jul 2021 – Jun 2022)',
  'TY 2021 (Jul 2020 – Jun 2021)',
  'TY 2020 (Jul 2019 – Jun 2020)',
];

class ClientDetailsScreen extends ConsumerStatefulWidget {
  const ClientDetailsScreen({super.key});

  @override
  ConsumerState<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends ConsumerState<ClientDetailsScreen> {
  final _clientNameController = TextEditingController();
  final _ntnController = TextEditingController();
  final _branchController = TextEditingController();
  final _thresholdController = TextEditingController();
  String? _taxYear;
  DateTime? _preparedDate;
  bool _saving = false;
  String? _saveMessage;
  bool _hydrated = false;
  bool _autoFillAttempted = false;

  List<MonthlySummary>? _monthlySummary;
  bool _loadingSummary = false;

  @override
  void dispose() {
    _clientNameController.dispose();
    _ntnController.dispose();
    _branchController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _hydrateFromState(SessionState session) {
    if (_hydrated) return;
    _hydrated = true;
    _clientNameController.text = session.clientName ?? '';
    _ntnController.text = session.ntn ?? '';
    _branchController.text = session.branch ?? '';
    _thresholdController.text = session.largeTransactionThreshold?.toStringAsFixed(0) ?? '';
    _taxYear = session.taxYear;
    _preparedDate = session.preparedDate != null ? DateTime.tryParse(session.preparedDate!) : null;
  }

  /// Auto-fills Client Name/Branch from the primary (first) account's
  /// extracted account title/branch -- only into fields the user hasn't
  /// already typed something into, mirroring the HTML source's own guard
  /// exactly. Runs once per screen visit; a manual edit afterward is
  /// never overwritten since this never runs again for the same visit.
  Future<void> _autoFillFromStatement(SessionState session) async {
    if (_autoFillAttempted || session.sessionId == null || session.members.isEmpty) return;
    _autoFillAttempted = true;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/${session.sessionId}/verification');
      final accounts = (response.data['accounts'] as List<dynamic>?) ?? [];
      if (accounts.isEmpty) return;
      final primary = accounts.first as Map<String, dynamic>;
      final bankSummary = primary['bank_summary'] as Map<String, dynamic>? ?? {};
      final accountTitle = bankSummary['account_title'] as String?;
      final branch = bankSummary['branch'] as String?;
      if (!mounted) return;
      setState(() {
        if (_clientNameController.text.trim().isEmpty && accountTitle != null && accountTitle.trim().isNotEmpty) {
          _clientNameController.text = accountTitle;
        }
        if (_branchController.text.trim().isEmpty && branch != null && branch.trim().isNotEmpty) {
          _branchController.text = branch;
        }
      });
    } catch (_) {
      // Best-effort only -- the fields simply stay editable/empty if this fails.
    }
  }

  Future<void> _loadMonthlySummary(SessionState session) async {
    if (session.sessionId == null || _loadingSummary || _monthlySummary != null) return;
    setState(() => _loadingSummary = true);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/${session.sessionId}/monthly-summary');
      final rows = (response.data as List<dynamic>).cast<Map<String, dynamic>>().map(MonthlySummary.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _monthlySummary = rows;
        _loadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSummary = false);
    }
  }

  /// Parses "TY 2024 (Jul 2023 – Jun 2024)" into (2023, 2024) -- the
  /// label's 2nd and 3rd 4-digit numbers are always the Jul-start-year
  /// and Jun-end-year respectively (the 1st is just the TY digits).
  (int, int)? _taxYearRange(String? label) {
    if (label == null) return null;
    final years = RegExp(r'\d{4}').allMatches(label).map((m) => int.parse(m.group(0)!)).toList();
    if (years.length < 3) return null;
    return (years[1], years[2]);
  }

  bool _monthInRange(String monthKey, (int, int) range) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return false;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return false;
    final (startYear, endYear) = range;
    if (year == startYear) return month >= 7;
    if (year == endYear) return month <= 6;
    return year > startYear && year < endYear;
  }

  Widget? _taxYearHint() {
    final summary = _monthlySummary;
    if (summary == null) return null;
    final total = summary.fold<int>(0, (s, r) => s + r.transactionCount);
    if (total == 0) return null;
    final range = _taxYearRange(_taxYear);
    if (range == null) {
      return Text(
        'Select a tax year to see how many of your transactions fall within it.',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
      );
    }
    final inRange = summary.where((r) => _monthInRange(r.month, range)).fold<int>(0, (s, r) => s + r.transactionCount);
    final outCount = total - inRange;
    if (outCount > 0) {
      return Text(
        '⚠ $inRange of $total transactions fall within this tax year — $outCount transaction(s) fall outside it.',
        style: const TextStyle(fontSize: 11.5, color: AppColors.orange, height: 1.4),
      );
    }
    return Text(
      '✓ All $total transactions fall within this tax year.',
      style: const TextStyle(fontSize: 11.5, color: AppColors.green, height: 1.4),
    );
  }

  Future<void> _pickPreparedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _preparedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _preparedDate = picked);
  }

  Future<bool> _save() async {
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    final threshold = double.tryParse(_thresholdController.text.trim());
    final ok = await ref.read(sessionControllerProvider.notifier).updateClientDetails(
          clientName: _clientNameController.text.trim(),
          ntn: _ntnController.text.trim(),
          taxYear: _taxYear,
          branch: _branchController.text.trim(),
          preparedDate: _preparedDate?.toIso8601String().split('T').first,
          largeTransactionThreshold: threshold,
        );
    if (!mounted) return ok;
    setState(() {
      _saving = false;
      _saveMessage = ok ? 'Saved.' : null;
    });
    return ok;
  }

  Future<void> _next() async {
    final ok = await _save();
    if (ok && mounted) context.go('/review');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    _hydrateFromState(session);
    _autoFillFromStatement(session);
    _loadMonthlySummary(session);
    final hint = _taxYearHint();

    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 1,
            labels: wizardStepLabels,
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 2) context.go('/review');
              if (i == 3 && session.sessionId != null) context.go('/verify');
              if (i == 4 && session.sessionId != null) context.go('/summary');
              if (i == 5 && session.sessionId != null) context.go('/reports');
            },
          ),
          Expanded(
            child: AppMain(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppCardHeader(
                      icon: '🧾',
                      title: 'Client Details',
                      subtitle: 'Auto-filled from the statement — edit anything that needs correcting.',
                    ),
                    if (session.errorMessage != null) AppAlert(kind: AppAlertKind.error, message: session.errorMessage!),
                    if (_saveMessage != null) AppAlert(kind: AppAlertKind.success, message: _saveMessage!),
                    _field('Client Name', _clientNameController, hint: 'Auto-detected from statement'),
                    _field('NTN', _ntnController, hint: 'e.g. 1234567-8'),
                    const SizedBox(height: 8),
                    Text('TAX YEAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _taxYear,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        for (final option in taxYearOptions) DropdownMenuItem(value: option, child: Text(option, style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (value) => setState(() => _taxYear = value),
                    ),
                    if (hint != null) Padding(padding: const EdgeInsets.only(top: 6), child: hint),
                    const SizedBox(height: 12),
                    _field('Branch', _branchController, hint: 'Auto-detected from statement'),
                    const SizedBox(height: 8),
                    Text('PREPARED DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickPreparedDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(isDense: true),
                        child: Text(
                          _preparedDate == null ? 'Select a date' : _preparedDate!.toIso8601String().split('T').first,
                          style: TextStyle(fontSize: 13, color: _preparedDate == null ? AppColors.muted : AppColors.text),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _field('Large Transaction Threshold', _thresholdController, keyboardType: TextInputType.number),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton(onPressed: () => context.go('/upload'), child: const Text('← Back')),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: _saving || session.sessionId == null ? null : _save,
                              child: Text(_saving ? 'Saving...' : 'Save'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: _saving || session.sessionId == null ? null : _next,
                              child: const Text('Next: Review Transactions →'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboardType, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 13, color: AppColors.heading),
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      ),
    );
  }
}
