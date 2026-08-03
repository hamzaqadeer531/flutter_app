import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/verification_models.dart';
import '../../state/auth_state.dart';
import '../../state/session_state.dart';
import '../../state/workflow_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/wizard_steps.dart';

const _sheetPreview = [
  ('📋', 'BANK WORKING', 'Header + Summary + Full Detail'),
  ('📈', 'CREDITS DETAIL', 'All credits categorized'),
  ('📉', 'DEBITS DETAIL', 'All debits categorized'),
  ('📅', 'MONTHLY SUMMARY', 'Month-by-month breakdown'),
  ('🚩', 'LARGE TRANSACTIONS', 'At/above your threshold'),
  ('🏦', 'ACCOUNTS SUMMARY', 'Multi-account only'),
  ('🔁', 'INTERNAL TRANSFERS', 'Own-account to own-account'),
  ('🔂', 'RECURRING TXNS', 'Repetitive transaction patterns'),
  ('🧾', 'EXECUTIVE SUMMARY', 'Key figures at a glance'),
];

/// Pixel-accurate migration of the HTML source's Step 6 ("Export") --
/// the combined multi-account Excel workbook + 3 CSV exports (HTML
/// feature-parity closure plan, Phase 8), session-scoped rather than
/// tied to a single active document.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  SessionVerification? _verification;
  bool _loadingVerification = true;
  String? _verificationError;

  bool _exporting = false;
  String? _status;
  bool _fileLocked = false;
  List<int>? _pendingBytes;
  String? _pendingPath;

  @override
  void initState() {
    super.initState();
    _loadVerification();
  }

  Future<void> _loadVerification() async {
    final sessionId = ref.read(sessionControllerProvider).sessionId;
    if (sessionId == null) {
      setState(() => _loadingVerification = false);
      return;
    }
    setState(() {
      _loadingVerification = true;
      _verificationError = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/$sessionId/verification');
      setState(() {
        _verification = SessionVerification.fromJson(response.data as Map<String, dynamic>);
        _loadingVerification = false;
      });
    } catch (error) {
      setState(() {
        _loadingVerification = false;
        _verificationError = 'Could not load export readiness: $error';
      });
    }
  }

  Future<void> _download(String path, String fileName, String suggestedExtension) async {
    setState(() {
      _exporting = true;
      _status = null;
      _fileLocked = false;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save export',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [suggestedExtension],
      );
      if (savePath == null) {
        setState(() => _status = 'Export cancelled.');
        return;
      }
      await _writeFile(savePath, response.data!);
    } catch (error) {
      setState(() => _status = 'Export failed: $error');
    } finally {
      setState(() => _exporting = false);
    }
  }

  /// Windows locks a file that's currently open in Excel — writing to
  /// it throws a sharing-violation FileSystemException instead of
  /// quietly succeeding. Rather than surface that as an opaque error,
  /// prompt the user to close the file and retry.
  Future<void> _writeFile(String path, List<int> bytes) async {
    try {
      await File(path).writeAsBytes(bytes);
      setState(() {
        _status = 'Saved to $path';
        _fileLocked = false;
        _pendingBytes = null;
        _pendingPath = null;
      });
    } on FileSystemException catch (error) {
      final locked = error.osError?.errorCode == 32 || error.osError?.errorCode == 33;
      if (!locked) rethrow;
      setState(() {
        _fileLocked = true;
        _pendingBytes = bytes;
        _pendingPath = path;
        _status = '"$path" is open in another program and can\'t be overwritten right now.';
      });
    }
  }

  Future<void> _retryLockedWrite() async {
    final bytes = _pendingBytes;
    final path = _pendingPath;
    if (bytes == null || path == null) return;
    await _writeFile(path, bytes);
  }

  void _newWorking() {
    ref.read(sessionControllerProvider.notifier).reset();
    ref.read(workflowControllerProvider.notifier).reset();
    context.go('/upload');
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = ref.watch(sessionControllerProvider).sessionId;

    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 5,
            labels: wizardStepLabels,
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 1) context.go('/client-details');
              if (i == 2) context.go('/review');
              if (i == 3) context.go('/verify');
              if (i == 4) context.go('/summary');
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
                      icon: '📊',
                      title: 'Generate Bank Working Excel',
                      subtitle: 'Your file will contain professionally formatted sheets, including Internal '
                          'Transfers and Recurring Transactions when detected.',
                    ),
                    if (sessionId == null)
                      const AppAlert(kind: AppAlertKind.warn, message: 'No working session yet -- upload a statement first.')
                    else ...[
                      _SheetPreviewGrid(),
                      const Divider(color: AppColors.border, height: 28),
                      if (_loadingVerification)
                        const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppColors.accent)))
                      else if (_verificationError != null)
                        AppAlert(kind: AppAlertKind.error, message: _verificationError!)
                      else if (_verification != null)
                        _ReadinessChecklist(verification: _verification!),
                      const Divider(color: AppColors.border, height: 28),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton(
                            onPressed: _exporting
                                ? null
                                : () => _download('/sessions/$sessionId/export-excel', 'working_$sessionId.xlsx', 'xlsx'),
                            child: const Text('⬇️ Download Complete Excel (.xlsx)'),
                          ),
                          OutlinedButton(
                            onPressed: _exporting
                                ? null
                                : () => _download('/sessions/$sessionId/export-csv/all', 'transactions_$sessionId.csv', 'csv'),
                            child: const Text('⬇️ All Transactions (.csv)'),
                          ),
                          OutlinedButton(
                            onPressed: _exporting
                                ? null
                                : () => _download('/sessions/$sessionId/export-csv/internal-transfers',
                                    'internal_transfers_$sessionId.csv', 'csv'),
                            child: const Text('⬇️ Internal Transfers (.csv)'),
                          ),
                          OutlinedButton(
                            onPressed: _exporting
                                ? null
                                : () => _download('/sessions/$sessionId/export-csv/recurring',
                                    'recurring_transactions_$sessionId.csv', 'csv'),
                            child: const Text('⬇️ Recurring Transactions (.csv)'),
                          ),
                          OutlinedButton(
                            onPressed: _exporting
                                ? null
                                : () => _download('/sessions/$sessionId/export-pdf', 'analysis_report_$sessionId.pdf', 'pdf'),
                            child: const Text('🖨️ Complete Analysis Report (.pdf)'),
                          ),
                          OutlinedButton(onPressed: _newWorking, child: const Text('🔄 New Working')),
                        ],
                      ),
                      if (_status != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: AppAlert(kind: _fileLocked ? AppAlertKind.warn : AppAlertKind.info, message: _status!),
                        ),
                      if (_fileLocked)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton(onPressed: _retryLockedWrite, child: const Text('Close the file, then Retry')),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(onPressed: () => context.go('/summary'), child: const Text('← Back')),
                ElevatedButton(onPressed: () => context.go('/dashboard'), child: const Text('Done')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetPreviewGrid extends StatelessWidget {
  const _SheetPreviewGrid();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (icon, name, desc) in _sheetPreview)
          Container(
            width: 160,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.panel2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 6),
                Text(name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReadinessChecklist extends StatelessWidget {
  const _ReadinessChecklist({required this.verification});

  final SessionVerification verification;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(verification.exportReady ? '✅ Ready to export' : '⏳ Not ready to export yet',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.heading)),
        const SizedBox(height: 8),
        for (final item in verification.checklist)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(item.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16, color: item.ok ? AppColors.green : AppColors.muted),
                const SizedBox(width: 8),
                Text(item.label, style: const TextStyle(fontSize: 13, color: AppColors.text)),
              ],
            ),
          ),
      ],
    );
  }
}
