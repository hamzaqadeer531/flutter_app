import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/workflow_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/wizard_steps.dart';

const _ocrEngineOptions = [
  ('tesseract', 'Auto (Tesseract OCR)'),
  ('pdf_text_layer', 'Digital PDF — Text Layer (no OCR)'),
];

const _bankOptions = [
  'Auto-Detect Bank (Recommended)',
  'Meezan Bank',
  'HBL – Habib Bank Limited',
  'UBL – United Bank Limited',
  'Askari Bank',
  'Bank Alfalah',
  'Bank AL Habib (BAHL)',
  'Bank Islami',
  'Habib Metropolitan Bank',
  'MCB – Muslim Commercial Bank',
  'ABL – Allied Bank Limited',
  'NBP – National Bank of Pakistan',
  'Other',
];

/// Pixel-accurate migration of the HTML source's Step 1 ("Upload Bank
/// Statement PDF") panel, including the inline OCR/parse progress UI
/// (`#parseProgress`) that was originally a spinner+progress-bar section
/// within this same panel — not a separate screen — matching that here.
class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String _selectedBank = _bankOptions.first;
  String _selectedEngine = _ocrEngineOptions.first.$1;
  bool _dragging = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xlsx', 'xls', 'csv', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true, // web has no real file path -- this is the only way to get the bytes there
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;

    // file_picker's PlatformFile.path GETTER THROWS on web (not just null)
    // -- merely evaluating file.path there crashes immediately, so kIsWeb
    // must gate which branch is taken, not a null-check on .path itself.
    if (kIsWeb) {
      if (file.bytes == null) return;
      await ref.read(workflowControllerProvider.notifier).uploadAndProcess(
            fileBytes: file.bytes,
            filename: file.name,
            bank: _selectedBank,
            ocrEngine: _selectedEngine,
          );
      return;
    }

    if (file.path == null) return;
    await ref.read(workflowControllerProvider.notifier).uploadAndProcess(
          filePath: file.path,
          filename: file.name,
          bank: _selectedBank,
          ocrEngine: _selectedEngine,
        );
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    final file = details.files.first;
    await ref.read(workflowControllerProvider.notifier).uploadAndProcess(
          filePath: file.path,
          filename: file.name,
          bank: _selectedBank,
          ocrEngine: _selectedEngine,
        );
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(workflowControllerProvider);

    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 0,
            labels: const ['Upload Statement', 'Review Transactions', 'Analytics & Export'],
            onStepTap: (i) {
              if (i == 1 && workflow.statement != null) context.go('/review');
              if (i == 2 && workflow.statement != null) context.go('/summary');
            },
          ),
          Expanded(
            child: AppMain(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppCardHeader(
                          icon: '📄',
                          title: 'Upload Bank Statement PDF',
                          subtitle: 'Select your bank below, then upload the PDF — all details are extracted automatically',
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('BANK *',
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
                                  const SizedBox(height: 5),
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedBank,
                                    dropdownColor: AppColors.panel2,
                                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                                    items: [
                                      for (final bank in _bankOptions)
                                        DropdownMenuItem(value: bank, child: Text(bank)),
                                    ],
                                    onChanged: workflow.isBusy ? null : (v) => setState(() => _selectedBank = v!),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('OCR ENGINE',
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
                                  const SizedBox(height: 5),
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedEngine,
                                    dropdownColor: AppColors.panel2,
                                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                                    items: [
                                      for (final engine in _ocrEngineOptions)
                                        DropdownMenuItem(value: engine.$1, child: Text(engine.$2)),
                                    ],
                                    onChanged: workflow.isBusy ? null : (v) => setState(() => _selectedEngine = v!),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const AppAlert(
                          kind: AppAlertKind.info,
                          icon: '✅',
                          message:
                              'Leave "Auto-Detect" selected and the bank, account type and statement type are all identified automatically. '
                              'Most bank-generated PDFs have an exact embedded text layer — if the default OCR reading looks off, try '
                              '"Digital PDF — Text Layer" instead (or vice versa) using the button shown after processing.',
                        ),
                        const SizedBox(height: 6),
                        if (!workflow.isBusy && workflow.statement == null)
                          DropTarget(
                            onDragEntered: (_) => setState(() => _dragging = true),
                            onDragExited: (_) => setState(() => _dragging = false),
                            onDragDone: _handleDrop,
                            child: InkWell(
                              onTap: _pickFile,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: AppColors.panel2,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _dragging ? AppColors.accent : AppColors.border,
                                    width: 2.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Text('📂', style: TextStyle(fontSize: 44)),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Drop PDF, Excel, CSV or a photo/image here — or click to browse',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.heading),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Works with text-based / scanned PDF, .xlsx, .xls, .csv, and photos or scans of statements',
                                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 14),
                                    ElevatedButton(onPressed: _pickFile, child: const Text('Choose File(s)')),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (workflow.isBusy)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(workflow.progressMessage ?? 'Processing...',
                                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const LinearProgressIndicator(color: AppColors.accent, backgroundColor: AppColors.gray),
                              ],
                            ),
                          ),
                        if (workflow.stage == WorkflowStage.failed)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: AppAlert(
                              kind: AppAlertKind.error,
                              message: workflow.errorMessage ?? 'Something went wrong while processing the statement.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (workflow.statement != null) _ExtractedDetailsCard(workflow: workflow),
                  if (workflow.statement != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            final otherEngine = _selectedEngine == 'tesseract' ? 'pdf_text_layer' : 'tesseract';
                            setState(() => _selectedEngine = otherEngine);
                            ref.read(workflowControllerProvider.notifier).reprocessWithEngine(otherEngine);
                          },
                          child: Text(
                            _selectedEngine == 'tesseract'
                                ? 'Result looks off? Try Digital PDF — Text Layer'
                                : 'Result looks off? Try Tesseract OCR',
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => context.go('/review'),
                          child: const Text('Next: Review Transactions →'),
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

class _ExtractedDetailsCard extends StatelessWidget {
  const _ExtractedDetailsCard({required this.workflow});

  final WorkflowState workflow;

  @override
  Widget build(BuildContext context) {
    final statement = workflow.statement!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCardHeader(
            icon: '✅',
            title: 'Extracted Statement Details',
            subtitle: 'Auto-detected — review and edit if needed',
            iconBackground: AppColors.greenSubtle,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metaTile('Account Title', statement.accountTitle ?? '—'),
              _metaTile('Account Number', statement.accountNumber ?? '—'),
              _metaTile('Transactions Found', '${statement.transactions.length}'),
              _metaTile('Opening Balance', statement.openingBalance?.toStringAsFixed(2) ?? '—'),
              _metaTile('Closing Balance', statement.closingBalance?.toStringAsFixed(2) ?? '—'),
              _metaTile('Confidence', '${(statement.confidence * 100).toStringAsFixed(1)}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaTile(String key, String value) {
    return Container(
      width: 200,
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
}
