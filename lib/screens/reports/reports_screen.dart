import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../state/workflow_state.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/wizard_steps.dart';

/// Pixel-accurate migration of the HTML source's Step 6 ("Export") —
/// downloads the real 7-sheet Excel workbook from
/// GET /transactions/{document_id}/export-excel (Phase 6 Part J).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _exporting = false;
  String? _status;
  bool _fileLocked = false;
  List<int>? _pendingBytes;
  String? _pendingPath;

  Future<void> _exportExcel(String documentId) async {
    setState(() {
      _exporting = true;
      _status = null;
      _fileLocked = false;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get<List<int>>(
        '/transactions/$documentId/export-excel',
        options: Options(responseType: ResponseType.bytes),
      );
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save bank statement workbook',
        fileName: 'bank_statement_$documentId.xlsx',
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

  /// Windows locks a workbook that's currently open in Excel — writing to
  /// it throws a sharing-violation FileSystemException instead of quietly
  /// succeeding. Rather than surface that as an opaque error, prompt the
  /// user to close the file and retry, the same safeguard a well-behaved
  /// desktop export tool gives you.
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
        _status = '"$path" is open in Excel (or another program) and can\'t be overwritten right now.';
      });
    }
  }

  Future<void> _retryLockedWrite() async {
    final bytes = _pendingBytes;
    final path = _pendingPath;
    if (bytes == null || path == null) return;
    await _writeFile(path, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(workflowControllerProvider);
    final documentId = workflow.documentId;

    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 2,
            labels: const ['Upload Statement', 'Review Transactions', 'Analytics & Export'],
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 1) context.go('/review');
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
                      icon: '📤',
                      title: 'Export',
                      subtitle: 'Download the full 7-sheet bank statement workbook.',
                    ),
                    if (documentId == null)
                      const AppAlert(kind: AppAlertKind.warn, message: 'No processed statement in this session yet.')
                    else ...[
                      ElevatedButton(
                        onPressed: _exporting ? null : () => _exportExcel(documentId),
                        child: Text(_exporting ? 'Exporting…' : 'Download Excel Workbook (.xlsx)'),
                      ),
                      if (_status != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: AppAlert(
                            kind: _fileLocked ? AppAlertKind.warn : AppAlertKind.info,
                            message: _status!,
                          ),
                        ),
                      if (_fileLocked)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton(
                            onPressed: _retryLockedWrite,
                            child: const Text('Close the file, then Retry'),
                          ),
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
