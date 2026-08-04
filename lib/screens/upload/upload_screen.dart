import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/session_state.dart';
import '../../state/workflow_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/wizard_steps.dart';

/// null (the "Auto" option) means "don't force an engine" -- the
/// backend's own ocr/document_intelligence_router.py then tries direct
/// PDF text extraction first (fast, no OCR misreads on dense tables)
/// and only falls back to Tesseract for a genuine scan/image. This
/// used to hardcode 'tesseract' for "Auto", which silently forced OCR
/// on every upload (including plain digital PDFs the router would
/// otherwise have skipped straight to text extraction) and bypassed
/// the router entirely -- a real bug, not the intended behavior (see
/// that module's own docstring: "whenever the caller didn't force a
/// specific engine").
const _ocrEngineOptions = [
  (null, 'Auto (Recommended)'),
  ('pdf_text_layer', 'Force Digital PDF — Text Layer (no OCR)'),
  ('tesseract', 'Force OCR (Tesseract)'),
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
  String? _selectedEngine = _ocrEngineOptions.first.$1;
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
    final session = ref.watch(sessionControllerProvider);

    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 0,
            labels: wizardStepLabels,
            onStepTap: (i) {
              if (i == 1 && session.sessionId != null) context.go('/client-details');
              if (i == 2 && workflow.statement != null) context.go('/review');
              if (i == 3 && session.sessionId != null) context.go('/verify');
              if (i == 4 && workflow.statement != null) context.go('/summary');
              if (i == 5 && workflow.statement != null) context.go('/reports');
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
                                  DropdownButtonFormField<String?>(
                                    initialValue: _selectedEngine,
                                    dropdownColor: AppColors.panel2,
                                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                                    items: [
                                      for (final engine in _ocrEngineOptions)
                                        DropdownMenuItem(value: engine.$1, child: Text(engine.$2)),
                                    ],
                                    onChanged: workflow.isBusy ? null : (v) => setState(() => _selectedEngine = v),
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
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: () => ref.read(workflowControllerProvider.notifier).reset(),
                              child: const Text('➕ Add Another Statement'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () => context.go('/client-details'),
                              child: const Text('Next: Client Details →'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  if (session.members.isNotEmpty) _UploadedStatementsCard(members: session.members),
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

/// "Uploaded Statements" queue (HTML feature-parity closure plan, Phase
/// 3) -- matches the HTML source's Step 1 accountStatements table
/// (Bank/File/Status/Remove per row; Txns/Credits/Debits are left for a
/// later phase once a lightweight per-member summary is worth fetching
/// -- see SessionMemberSummary's own doc comment for why this stays
/// client-side-only for now).
class _UploadedStatementsCard extends ConsumerWidget {
  const _UploadedStatementsCard({required this.members});

  final List<SessionMemberSummary> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCardHeader(
            icon: '🗂️',
            title: 'Uploaded Statements',
            subtitle: '${members.length} statement(s) in this working session',
          ),
          for (final member in members)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(member.bankHint ?? 'Auto-Detect', style: const TextStyle(fontSize: 12.5, color: AppColors.heading)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(member.filename, style: TextStyle(fontSize: 12.5, color: AppColors.muted), overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    flex: 1,
                    child: _statusChip(member.status),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: AppColors.muted),
                    tooltip: 'Remove this statement',
                    onPressed: () => ref.read(sessionControllerProvider.notifier).removeMember(member.documentId),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'ready' => ('✓ Ready', AppColors.green),
      'failed' => ('✕ Failed', AppColors.red),
      _ => ('⏳ Processing', AppColors.orange),
    };
    return Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600));
  }
}
