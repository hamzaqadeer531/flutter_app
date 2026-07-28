import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/pipeline_models.dart';
import '../../state/workflow_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/wizard_steps.dart';

enum _Filter { all, credits, debits }

enum _CellStatus { none, success, error }

/// Pixel-accurate migration of the HTML source's Step 3 ("Review &
/// Categorize Transactions") — filter buttons, search bar, and an
/// editable transaction table with inline debit/credit values.
///
/// The table cells are wired to the real backend (POST /review/{id}/
/// transaction/edit) — previously this screen's subtitle promised
/// inline editing but every cell was a plain, non-interactive Text
/// widget with zero API calls anywhere in the file.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  _Filter _filter = _Filter.all;
  String _search = '';

  /// Keyed by "${transaction.rowKey}|$fieldName" -- lives here (not
  /// inside each cell widget) because a successful edit changes the
  /// underlying value, which recreates the cell widget (see
  /// _EditableCell's ValueKey below) and would otherwise lose the
  /// "just saved" checkmark the instant it appears.
  final Map<String, _CellStatus> _cellStatus = {};

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(workflowControllerProvider);
    final statement = workflow.statement;

    if (statement == null) {
      return AppShell(
        body: AppMain(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No statement loaded yet.',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.heading)),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: () => context.go('/upload'), child: const Text('Upload a statement')),
              ],
            ),
          ),
        ),
      );
    }

    final txns = statement.transactions.where((t) {
      if (_filter == _Filter.credits && t.credit == null) return false;
      if (_filter == _Filter.debits && t.debit == null) return false;
      if (_search.isNotEmpty && !t.description.toLowerCase().contains(_search.toLowerCase())) return false;
      return true;
    }).toList();

    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 1,
            labels: const ['Upload Statement', 'Review Transactions', 'Analytics & Export'],
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 2) context.go('/summary');
            },
          ),
          Expanded(
            child: AppMain(
              child: AppCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppCardHeader(
                      icon: '🔍',
                      title: 'Review & Categorize Transactions',
                      subtitle: 'Correct debit/credit, amounts, or descriptions inline before exporting — '
                          'click a cell, edit it, then press Enter or click away to save.',
                    ),
                    Row(
                      children: [
                        _filterButton('All', _Filter.all),
                        const SizedBox(width: 6),
                        _filterButton('Credits Only', _Filter.credits),
                        const SizedBox(width: 6),
                        _filterButton('Debits Only', _Filter.debits),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
                              hintText: 'Search description, amount, reference...',
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text('${txns.length} of ${statement.transactions.length} shown',
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: txns.isEmpty
                          ? Center(
                              child: Text('No transactions match this filter.',
                                  style: TextStyle(color: AppColors.muted)),
                            )
                          : _buildTable(txns),
                    ),
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
                OutlinedButton(onPressed: () => context.go('/upload'), child: const Text('← Back')),
                ElevatedButton(onPressed: () => context.go('/summary'), child: const Text('Next: Analytics & Export →')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String label, _Filter value) {
    final active = _filter == value;
    return OutlinedButton(
      onPressed: () => setState(() => _filter = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? AppColors.navy : AppColors.panel2,
        foregroundColor: active ? Colors.white : AppColors.text,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildTable(List<PipelineTransaction> transactions) {
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(110),
          1: FlexColumnWidth(),
          2: FixedColumnWidth(120),
          3: FixedColumnWidth(120),
          4: FixedColumnWidth(120),
          5: FixedColumnWidth(40),
        },
        border: TableBorder(horizontalInside: BorderSide(color: AppColors.border)),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.navy),
            children: [
              _headerCell('Date'),
              _headerCell('Description'),
              _headerCell('Debit'),
              _headerCell('Credit'),
              _headerCell('Balance'),
              _headerCell(''),
            ],
          ),
          for (final t in transactions)
            TableRow(
              children: [
                _editableCell(t, 'date_iso', t.dateIso ?? ''),
                _editableCell(t, 'description', t.description, alignLeft: true),
                _editableCell(t, 'debit', _formatAmount(t.debit), color: AppColors.red),
                _editableCell(t, 'credit', _formatAmount(t.credit), color: AppColors.green),
                _editableCell(t, 'balance', _formatAmount(t.balance)),
                _flagButton(t),
              ],
            ),
        ],
      ),
    );
  }

  Widget _flagButton(PipelineTransaction transaction) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.flag_outlined, size: 16, color: AppColors.muted),
      tooltip: 'Flag a problem with this row',
      onSelected: (errorKind) => _promptForNoteAndFlag(transaction, errorKind),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'ocr', child: Text('OCR misread this row', style: TextStyle(fontSize: 12))),
        PopupMenuItem(value: 'parser', child: Text('Parser split/grouped this row wrong', style: TextStyle(fontSize: 12))),
        PopupMenuItem(value: 'classification', child: Text('Category/name is wrong', style: TextStyle(fontSize: 12))),
      ],
    );
  }

  Future<void> _promptForNoteAndFlag(PipelineTransaction transaction, String errorKind) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flag this row'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Optional note (what looks wrong?)'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Flag'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return; // cancelled

    try {
      await ref.read(workflowControllerProvider.notifier).markTransactionError(
            transaction: transaction,
            errorKind: errorKind,
            note: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flagged for review.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not flag this row: $error');
    }
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  String _formatAmount(double? value) => value == null ? '' : value.toStringAsFixed(2);

  Widget _editableCell(
    PipelineTransaction transaction,
    String fieldName,
    String currentValue, {
    bool alignLeft = false,
    Color? color,
  }) {
    final statusKey = '${transaction.rowKey}|$fieldName';
    return _EditableCell(
      // Recreated whenever the saved value changes, so a fresh
      // TextField always starts from the latest server-confirmed
      // value instead of fighting a stale controller.
      key: ValueKey('$statusKey|$currentValue'),
      initialValue: currentValue,
      alignLeft: alignLeft,
      color: color,
      status: _cellStatus[statusKey] ?? _CellStatus.none,
      onSubmit: (newValue) => _submitEdit(transaction, fieldName, currentValue, newValue, statusKey),
    );
  }

  Future<void> _submitEdit(
    PipelineTransaction transaction,
    String fieldName,
    String originalValue,
    String correctedValue,
    String statusKey,
  ) async {
    if (fieldName == 'debit' || fieldName == 'credit' || fieldName == 'balance') {
      if (double.tryParse(correctedValue.replaceAll(',', '')) == null) {
        setState(() => _cellStatus[statusKey] = _CellStatus.error);
        _showError('"$correctedValue" isn\'t a valid amount.');
        return;
      }
    }
    try {
      await ref.read(workflowControllerProvider.notifier).editTransactionField(
            transaction: transaction,
            fieldName: fieldName,
            originalValue: originalValue.isEmpty ? null : originalValue,
            correctedValue: correctedValue,
          );
      if (!mounted) return;
      setState(() => _cellStatus[statusKey] = _CellStatus.success);
    } catch (error) {
      if (!mounted) return;
      setState(() => _cellStatus[statusKey] = _CellStatus.error);
      _showError('Could not save: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.red),
    );
  }
}

class _EditableCell extends StatefulWidget {
  const _EditableCell({
    super.key,
    required this.initialValue,
    required this.alignLeft,
    required this.color,
    required this.status,
    required this.onSubmit,
  });

  final String initialValue;
  final bool alignLeft;
  final Color? color;
  final _CellStatus status;
  final Future<void> Function(String newValue) onSubmit;

  @override
  State<_EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<_EditableCell> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);
  late final FocusNode _focusNode = FocusNode();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _trySubmit();
  }

  Future<void> _trySubmit() async {
    final newValue = _controller.text.trim();
    if (newValue == widget.initialValue || _submitting) return;
    setState(() => _submitting = true);
    await widget.onSubmit(newValue);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlign: widget.alignLeft ? TextAlign.left : TextAlign.right,
              style: TextStyle(fontSize: 12.5, color: widget.color ?? AppColors.text),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              ),
              onSubmitted: (_) => _trySubmit(),
            ),
          ),
          SizedBox(
            width: 14,
            child: _submitting
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : widget.status == _CellStatus.success
                    ? Icon(Icons.check_circle, size: 14, color: AppColors.green)
                    : widget.status == _CellStatus.error
                        ? Icon(Icons.error, size: 14, color: AppColors.red)
                        : null,
          ),
        ],
      ),
    );
  }
}
