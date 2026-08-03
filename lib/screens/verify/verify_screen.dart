import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/verification_models.dart';
import '../../state/auth_state.dart';
import '../../state/session_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/wizard_steps.dart';

/// Verify & Check (HTML feature-parity closure plan, Phase 4) -- step 4
/// of the 6-step wizard. Per-account balance reconciliation, the 14-
/// field Bank Summary block, and Credit/Debit category summaries, all
/// backed by GET /sessions/{id}/verification (services.
/// verification_service.VerificationService -- reuses the existing
/// balance validator and category-summary engine, not new logic).
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  SessionVerification? _verification;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessionId = ref.read(sessionControllerProvider).sessionId;
    if (sessionId == null) {
      setState(() {
        _loading = false;
        _error = 'No working session yet -- upload a statement first.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/$sessionId/verification');
      setState(() {
        _verification = SessionVerification.fromJson(response.data as Map<String, dynamic>);
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Could not load verification: $error';
      });
    }
  }

  Future<void> _editBalance(String documentId, String fieldName, String? original, String correctedValue) async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.post('/review/$documentId/statement-metadata/edit', data: {
        'field_name': fieldName,
        'original_value': original,
        'corrected_value': correctedValue,
      });
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 3,
            labels: wizardStepLabels,
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 1) context.go('/client-details');
              if (i == 2) context.go('/review');
              if (i == 4) context.go('/summary');
              if (i == 5) context.go('/reports');
            },
          ),
          Expanded(
            child: AppMain(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _error != null
                      ? AppAlert(kind: AppAlertKind.error, message: _error!)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ChecklistCard(verification: _verification!),
                            for (final account in _verification!.accounts)
                              _AccountCard(account: account, onEditBalance: _editBalance),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OutlinedButton(onPressed: () => context.go('/review'), child: const Text('← Back')),
                                ElevatedButton(
                                  onPressed: () => context.go('/summary'),
                                  child: const Text('Next: Analytics & Insights →'),
                                ),
                              ],
                            ),
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.verification});

  final SessionVerification verification;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCardHeader(
            icon: verification.exportReady ? '✅' : '⏳',
            title: 'Export Readiness',
            subtitle: verification.exportReady ? 'Ready to export.' : 'Not ready to export yet.',
          ),
          for (final item in verification.checklist)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(item.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16, color: item.ok ? AppColors.green : AppColors.muted),
                  const SizedBox(width: 8),
                  Text(item.label, style: TextStyle(fontSize: 13, color: AppColors.text)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatefulWidget {
  const _AccountCard({required this.account, required this.onEditBalance});

  final AccountVerification account;
  final Future<void> Function(String documentId, String fieldName, String? original, String correctedValue) onEditBalance;

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  late final TextEditingController _openingController;
  late final TextEditingController _closingController;

  @override
  void initState() {
    super.initState();
    _openingController = TextEditingController(text: widget.account.bankSummary.openingBalance?.toStringAsFixed(2) ?? '');
    _closingController = TextEditingController(text: widget.account.bankSummary.closingBalance?.toStringAsFixed(2) ?? '');
  }

  @override
  void didUpdateWidget(covariant _AccountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _openingController.text = widget.account.bankSummary.openingBalance?.toStringAsFixed(2) ?? '';
    _closingController.text = widget.account.bankSummary.closingBalance?.toStringAsFixed(2) ?? '';
  }

  @override
  void dispose() {
    _openingController.dispose();
    _closingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final summary = account.bankSummary;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCardHeader(
            icon: account.reconciled ? '✅' : '⚠️',
            title: account.filename,
            subtitle: account.reconciled ? 'Balance reconciles.' : 'Balance does not reconcile — see warnings below.',
          ),
          for (final warning in account.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: AppAlert(kind: AppAlertKind.warn, message: warning.message),
            ),
          Row(
            children: [
              Expanded(
                child: _balanceField('Opening Balance', _openingController,
                    () => widget.onEditBalance(account.documentId, 'opening_balance', summary.openingBalance?.toString(), _openingController.text.trim())),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _balanceField('Closing Balance', _closingController,
                    () => widget.onEditBalance(account.documentId, 'closing_balance', summary.closingBalance?.toString(), _closingController.text.trim())),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('BANK SUMMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _tile('Bank Name', summary.bankName ?? '—'),
              _tile('Account Title', summary.accountTitle ?? '—'),
              _tile('Account Number', summary.accountNumber ?? '—'),
              _tile('Currency', summary.currency ?? '—'),
              _tile('Statement Period', _period(summary)),
              _tile('Total Credits', summary.totalCredits.toStringAsFixed(2)),
              _tile('Total Debits', summary.totalDebits.toStringAsFixed(2)),
              _tile('Net Movement', summary.netMovement.toStringAsFixed(2)),
              _tile('Credit Count', '${summary.creditCount}'),
              _tile('Debit Count', '${summary.debitCount}'),
              _tile('Extraction Confidence', '${(summary.extractionConfidence * 100).toStringAsFixed(1)}%'),
              _tile('Processed Date', summary.processedDate),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _summaryTable('Credit Summary', account.creditSummary)),
              const SizedBox(width: 16),
              Expanded(child: _summaryTable('Debit Summary', account.debitSummary)),
            ],
          ),
        ],
      ),
    );
  }

  String _period(BankSummary summary) {
    if (summary.statementPeriodStart == null && summary.statementPeriodEnd == null) return '—';
    return '${summary.statementPeriodStart ?? '?'} – ${summary.statementPeriodEnd ?? '?'}';
  }

  Widget _balanceField(String label, TextEditingController controller, VoidCallback onSave) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.muted)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13, color: AppColors.heading),
                decoration: const InputDecoration(isDense: true),
              ),
            ),
            IconButton(icon: const Icon(Icons.check, size: 16, color: AppColors.green), tooltip: 'Save', onPressed: onSave),
          ],
        ),
      ],
    );
  }

  Widget _tile(String key, String value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(color: AppColors.gray, borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(key.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.muted)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.heading)),
        ],
      ),
    );
  }

  Widget _summaryTable(String title, List<SummaryGroup> groups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        if (groups.isEmpty) Text('No transactions.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text('${g.category ?? "Uncategorized"} — ${g.name ?? "—"}', style: TextStyle(fontSize: 12, color: AppColors.text), overflow: TextOverflow.ellipsis)),
                Text('${g.count}×', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                const SizedBox(width: 8),
                Text(g.total.toStringAsFixed(2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.heading)),
              ],
            ),
          ),
      ],
    );
  }
}
