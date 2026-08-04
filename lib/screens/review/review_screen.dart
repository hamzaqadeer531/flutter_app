import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/pipeline_models.dart';
import '../../state/auth_state.dart';
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
  bool _verifying = false;
  bool _enhancingNames = false;
  bool _checkingMissing = false;
  bool _validatingWithAI = false;
  bool _recoveringWithAI = false;

  /// Keyed by rowKey. Selection is shared by two different actions with
  /// different backend gates: bulk-approve/bulk-reject (reviewer/admin
  /// only) and merge-rows (any authenticated user, get_current_user with
  /// no require_role) -- so the checkbox column itself is always shown,
  /// but which action buttons appear depends on role.
  final Set<String> _selectedRowKeys = {};
  bool _bulkActing = false;
  bool _merging = false;

  @override
  Widget build(BuildContext context) {
    // Soft, one-shot notice for the automatic post-upload name-enhancement
    // pass (workflow_state.dart::_runOcrLayoutParse) -- deliberately a
    // snackbar, not a persistent banner, since this never blocked the
    // upload itself and the manual "Enhance Names (AI)" button below
    // remains available as a retry.
    ref.listen<WorkflowState>(workflowControllerProvider, (previous, next) {
      if (next.nameEnhancementNote != null && next.nameEnhancementNote != previous?.nameEnhancementNote) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.nameEnhancementNote!), backgroundColor: AppColors.panel2),
        );
      }
    });
    final workflow = ref.watch(workflowControllerProvider);
    final statement = workflow.statement;
    final role = ref.watch(authControllerProvider).user?.role;
    final canBulkAct = role == 'reviewer' || role == 'admin';

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
            currentIndex: 2,
            labels: wizardStepLabels,
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 1) context.go('/client-details');
              if (i == 3) context.go('/verify');
              if (i == 4) context.go('/summary');
              if (i == 5) context.go('/reports');
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
                    if (_selectedRowKeys.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text('${_selectedRowKeys.length} selected',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          const SizedBox(width: 10),
                          if (canBulkAct) ...[
                            OutlinedButton(
                              onPressed: _bulkActing ? null : () => _bulkApprove(txns),
                              child: const Text('Approve Selected', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _bulkActing ? null : () => _bulkReject(txns),
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                              child: const Text('Reject Selected', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (_selectedRowKeys.length >= 2)
                            OutlinedButton(
                              onPressed: _merging ? null : () => _mergeSelected(txns),
                              child: const Text('Merge Selected Rows', style: TextStyle(fontSize: 12)),
                            ),
                          if (_bulkActing || _merging) ...[
                            const SizedBox(width: 10),
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                    ],
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
                Row(
                  children: [
                    Tooltip(
                      message: 'Runs an AI model over transactions the automatic name extraction '
                          'found nothing for, and fills in a counterparty name where confident.',
                      child: OutlinedButton(
                        onPressed: _enhancingNames ? null : _enhanceNames,
                        child: _enhancingNames
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('🧠 Enhance Names (AI)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Sends the original file to Gemini for an independent cross-check '
                          'against the local parse -- flags rows whose debit/credit or amount look wrong.',
                      child: OutlinedButton(
                        onPressed: _validatingWithAI ? null : _runAIValidation,
                        child: _validatingWithAI
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('🔍 AI Validate'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Fallback for a bad parse: asks Gemini to re-extract every transaction '
                          'from scratch. Staged -- nothing changes until you review and accept it, '
                          'and accepting REPLACES the whole transaction list.',
                      child: OutlinedButton(
                        onPressed: _recoveringWithAI ? null : _runAIRecovery,
                        child: _recoveringWithAI
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('🔮 AI Recovery'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Finds balance gaps between transactions -- somewhere a transaction the '
                          'parser missed likely belongs -- and lets you insert one to fill it.',
                      child: OutlinedButton(
                        onPressed: _checkingMissing ? null : _checkMissingTransactions,
                        child: _checkingMissing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('🔎 Missing Transactions'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: workflow.documentTypeId == null
                          ? 'This document could not be auto-classified, so it can\'t be verified.'
                          : 'Marks this document verified and trains a template from it.',
                      child: OutlinedButton(
                        onPressed: workflow.documentTypeId == null || _verifying ? null : _verify,
                        child: _verifying
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('✅ Verify Document'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(onPressed: () => context.go('/summary'), child: const Text('Next: Analytics & Export →')),
                  ],
                ),
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
    final allSelected =
        transactions.isNotEmpty && transactions.every((t) => _selectedRowKeys.contains(t.rowKey));
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(32),
          1: FixedColumnWidth(110),
          2: FlexColumnWidth(),
          3: FixedColumnWidth(120),
          4: FixedColumnWidth(120),
          5: FixedColumnWidth(120),
          6: FixedColumnWidth(84),
        },
        border: TableBorder(horizontalInside: BorderSide(color: AppColors.border)),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.navy),
            children: [
              Checkbox(
                value: allSelected,
                fillColor: WidgetStateProperty.all(Colors.white),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selectedRowKeys.addAll(transactions.map((t) => t.rowKey));
                  } else {
                    _selectedRowKeys.removeAll(transactions.map((t) => t.rowKey));
                  }
                }),
              ),
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
                Checkbox(
                  value: _selectedRowKeys.contains(t.rowKey),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _selectedRowKeys.add(t.rowKey);
                    } else {
                      _selectedRowKeys.remove(t.rowKey);
                    }
                  }),
                ),
                _editableCell(t, 'date_iso', t.dateIso ?? ''),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _editableCell(t, 'description', t.description, alignLeft: true),
                    if (t.isInserted)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2),
                        child: Text('🧩 Inserted by reviewer',
                            style: TextStyle(fontSize: 10, color: AppColors.muted, fontStyle: FontStyle.italic)),
                      ),
                    if (t.extractedName != null && t.extractedName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2),
                        child: Text(
                          t.nameSource == 'ner' ? '🧠 ${t.extractedName}' : t.extractedName!,
                          style: TextStyle(fontSize: 10, color: AppColors.muted, fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (t.thresholdFlagged)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2),
                        child: Text('🚩 Large transaction',
                            style: TextStyle(fontSize: 10, color: AppColors.orange, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
                _editableCell(t, 'debit', _formatAmount(t.debit), color: AppColors.red),
                _editableCell(t, 'credit', _formatAmount(t.credit), color: AppColors.green),
                _editableCell(t, 'balance', _formatAmount(t.balance)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _flagButton(t),
                    if (!t.isInserted) _sourceButton(t),
                    _layoutToolsButton(t),
                  ],
                ),
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

  Future<void> _bulkApprove(List<PipelineTransaction> visibleTransactions) async {
    final selected = visibleTransactions.where((t) => _selectedRowKeys.contains(t.rowKey)).toList();
    if (selected.isEmpty) return;
    setState(() => _bulkActing = true);
    try {
      await ref.read(workflowControllerProvider.notifier).bulkApproveTransactions(selected);
      if (!mounted) return;
      setState(() => _selectedRowKeys.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selected.length} transaction(s) approved.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not approve selection: $error');
    } finally {
      if (mounted) setState(() => _bulkActing = false);
    }
  }

  Future<void> _bulkReject(List<PipelineTransaction> visibleTransactions) async {
    final selected = visibleTransactions.where((t) => _selectedRowKeys.contains(t.rowKey)).toList();
    if (selected.isEmpty) return;

    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reject ${selected.length} transaction(s)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Optional note (why are these rejected?)'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return; // cancelled

    setState(() => _bulkActing = true);
    try {
      await ref.read(workflowControllerProvider.notifier).bulkRejectTransactions(
            selected,
            note: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      setState(() => _selectedRowKeys.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selected.length} transaction(s) rejected.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not reject selection: $error');
    } finally {
      if (mounted) setState(() => _bulkActing = false);
    }
  }

  Future<void> _mergeSelected(List<PipelineTransaction> visibleTransactions) async {
    final selected = visibleTransactions.where((t) => _selectedRowKeys.contains(t.rowKey)).toList();
    if (selected.length < 2) return;
    setState(() => _merging = true);
    try {
      await ref.read(workflowControllerProvider.notifier).mergeRows(selected);
      if (!mounted) return;
      setState(() => _selectedRowKeys.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selected.length} row(s) merged — takes effect on next reprocess.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not merge selection: $error');
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  Widget _sourceButton(PipelineTransaction transaction) {
    return IconButton(
      icon: Icon(Icons.travel_explore_outlined, size: 16, color: AppColors.muted),
      tooltip: 'Show OCR/layout/parser source for this row',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () {
        final documentId = ref.read(workflowControllerProvider).documentId;
        if (documentId == null) return;
        showDialog(
          context: context,
          builder: (context) => _SourceDialog(
            dio: ref.read(apiClientProvider).dio,
            documentId: documentId,
            transaction: transaction,
          ),
        );
      },
    );
  }

  Widget _layoutToolsButton(PipelineTransaction transaction) {
    // A reviewer-inserted row (see insertTransaction) has no real layout
    // cells behind it -- split/merge/split-cell all operate on actual
    // source_cell_ids, so none of them apply. Its only row-shape action
    // is undoing the insertion entirely.
    if (transaction.isInserted) {
      return PopupMenuButton<String>(
        icon: Icon(Icons.grid_view_outlined, size: 16, color: AppColors.muted),
        tooltip: 'This row was inserted by a reviewer',
        padding: EdgeInsets.zero,
        onSelected: (action) {
          if (action == 'retract') _retractInsertedRow(transaction);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'retract', child: Text('Retract this inserted row...', style: TextStyle(fontSize: 12))),
        ],
      );
    }
    return PopupMenuButton<String>(
      icon: Icon(Icons.grid_view_outlined, size: 16, color: AppColors.muted),
      tooltip: 'Split this row, merge cells, or split a cell',
      padding: EdgeInsets.zero,
      onSelected: (action) {
        switch (action) {
          case 'split_row':
            _splitRowDialog(transaction);
          case 'merge_cells':
            _mergeCellsDialog(transaction);
          case 'split_cell':
            _splitCellDialog(transaction);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'split_row', child: Text('Split this row...', style: TextStyle(fontSize: 12))),
        PopupMenuItem(value: 'merge_cells', child: Text('Merge cells in this row...', style: TextStyle(fontSize: 12))),
        PopupMenuItem(value: 'split_cell', child: Text('Split a cell...', style: TextStyle(fontSize: 12))),
      ],
    );
  }

  /// review.py's split-rows takes ONE row_ref (a transaction's
  /// sourceCellIds) and a set of resulting_refs -- how to redistribute
  /// those same cell ids into 2+ new rows. Cell ids are opaque strings
  /// with no associated display text in this model, so the UI is a
  /// plain "assign a group number to each cell id" list rather than a
  /// rendered grid.
  Future<void> _splitRowDialog(PipelineTransaction transaction) async {
    final cellIds = transaction.sourceCellIds;
    if (cellIds.isEmpty) {
      _showError('This row has no cell references to split.');
      return;
    }
    final groupControllers = {for (final id in cellIds) id: TextEditingController(text: '1')};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Split this row'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Give each cell a group number — cells sharing a number become one resulting row.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                for (final id in cellIds)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(id, style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: groupControllers[id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(isDense: true, hintText: 'Group'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Split')),
        ],
      ),
    );

    final groups = <String, List<String>>{};
    for (final id in cellIds) {
      final group = groupControllers[id]!.text.trim().isEmpty ? '1' : groupControllers[id]!.text.trim();
      groups.putIfAbsent(group, () => []).add(id);
    }
    for (final c in groupControllers.values) {
      c.dispose();
    }
    if (confirmed != true) return;

    if (groups.length < 2) {
      _showError('Enter at least two different group numbers to split this row.');
      return;
    }
    try {
      await ref.read(workflowControllerProvider.notifier).splitRows(transaction, groups.values.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Row split into ${groups.length} rows — takes effect on next reprocess.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not split row: $error');
    }
  }

  Future<void> _mergeCellsDialog(PipelineTransaction transaction) async {
    final cellIds = transaction.sourceCellIds;
    if (cellIds.length < 2) {
      _showError('This row does not have enough cell references to merge.');
      return;
    }
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Merge cells in this row'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final id in cellIds)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(id),
                      title: Text(id, style: const TextStyle(fontSize: 11.5)),
                      onChanged: (checked) => setDialogState(() {
                        if (checked ?? false) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Merge')),
          ],
        ),
      ),
    );
    if (confirmed != true || selected.length < 2) return;

    try {
      await ref.read(workflowControllerProvider.notifier).mergeCells(transaction, selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cells merged — takes effect on next reprocess.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not merge cells: $error');
    }
  }

  Future<void> _splitCellDialog(PipelineTransaction transaction) async {
    final cellIds = transaction.sourceCellIds;
    if (cellIds.isEmpty) {
      _showError('This row has no cell references to split.');
      return;
    }
    String selectedCellId = cellIds.first;
    final textController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Split a cell'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedCellId,
                  items: [
                    for (final id in cellIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(id, style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => selectedCellId = v ?? selectedCellId),
                ),
                const SizedBox(height: 10),
                Text('One resulting piece of text per line:', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Text piece 1\nText piece 2'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Split')),
          ],
        ),
      ),
    );
    final resultingTexts = textController.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    textController.dispose();
    if (confirmed != true || resultingTexts.length < 2) return;

    try {
      await ref.read(workflowControllerProvider.notifier).splitCells(transaction, selectedCellId, resultingTexts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cell split — takes effect on next reprocess.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not split cell: $error');
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

  Future<void> _enhanceNames() async {
    setState(() => _enhancingNames = true);
    try {
      await ref.read(workflowControllerProvider.notifier).enhanceNames();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name enhancement complete — check the Description column for newly filled names.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Name enhancement failed: $error');
    } finally {
      if (mounted) setState(() => _enhancingNames = false);
    }
  }

  Future<void> _runAIValidation() async {
    setState(() => _validatingWithAI = true);
    Map<String, dynamic> result;
    List<Map<String, dynamic>> parserWarnings;
    try {
      final notifier = ref.read(workflowControllerProvider.notifier);
      // Gemini's independent cross-check and the local deterministic
      // balance/duplicate validator are unrelated failure surfaces --
      // one failing shouldn't hide the other's real findings.
      final results = await Future.wait([
        notifier.validateWithAI(),
        notifier.fetchParserValidationWarnings().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      result = results[0] as Map<String, dynamic>;
      parserWarnings = results[1] as List<Map<String, dynamic>>;
    } catch (error) {
      if (!mounted) return;
      _showError('AI Validation failed: $error');
      return;
    } finally {
      if (mounted) setState(() => _validatingWithAI = false);
    }
    if (!mounted) return;
    final transactions = ref.read(workflowControllerProvider).statement?.transactions ?? const [];
    await showDialog(
      context: context,
      builder: (context) => _AIValidationDialog(
        result: result,
        parserWarnings: parserWarnings,
        transactions: transactions,
        onApply: (correction) async {
          try {
            await ref.read(workflowControllerProvider.notifier).applyAICorrection(
                  transactionRef: (correction['transaction_ref'] as List).cast<String>(),
                  kind: correction['kind'] as String,
                  suggestedValue: correction['suggested_value'] as Object,
                );
            return true;
          } catch (error) {
            if (!mounted) return false;
            _showError('Could not apply correction: $error');
            return false;
          }
        },
      ),
    );
  }

  Future<void> _runAIRecovery() async {
    setState(() => _recoveringWithAI = true);
    Map<String, dynamic> result;
    try {
      result = await ref.read(workflowControllerProvider.notifier).recoverWithAI();
    } catch (error) {
      if (!mounted) return;
      _showError('AI Recovery failed: $error');
      return;
    } finally {
      if (mounted) setState(() => _recoveringWithAI = false);
    }
    if (!mounted) return;

    final transactions = (result['transactions'] as List).cast<Map<String, dynamic>>();
    if (transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini did not recover any transactions from this file.')),
      );
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => _AIRecoveryDialog(result: result),
    );
    if (accepted != true) return;
    if (!mounted) return;

    final currentCount = ref.read(workflowControllerProvider).statement?.transactions.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all transactions?'),
        content: Text(
          'This replaces all $currentCount current transaction(s) with the ${transactions.length} '
          'Gemini recovered. Any un-exported review corrections on the replaced rows will no longer apply. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(workflowControllerProvider.notifier).acceptAIRecovery(transactions);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Replaced with ${transactions.length} recovered transaction(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not accept AI Recovery: $error');
    }
  }

  Future<void> _checkMissingTransactions() async {
    setState(() => _checkingMissing = true);
    List<Map<String, dynamic>> candidates;
    try {
      candidates = await ref.read(workflowControllerProvider.notifier).fetchMissingTransactionCandidates();
    } catch (error) {
      if (!mounted) return;
      _showError('Could not check for missing transactions: $error');
      return;
    } finally {
      if (mounted) setState(() => _checkingMissing = false);
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => _MissingTransactionsDialog(
        candidates: candidates,
        onInsert: (candidate) {
          Navigator.pop(context);
          _insertTransactionDialog(candidate: candidate);
        },
        onInsertManually: () {
          Navigator.pop(context);
          _insertTransactionDialog();
        },
      ),
    );
  }

  /// candidate (when given) is one entry from GET .../missing-
  /// transaction-candidates -- pre-fills the suggested debit/credit and
  /// the two bracketing dates as a starting point; description/exact
  /// date are always left for the reviewer to fill in, since nothing on
  /// the backend re-reads the source document to recover them.
  Future<void> _insertTransactionDialog({Map<String, dynamic>? candidate}) async {
    final dateController = TextEditingController(text: candidate?['prev_date_iso'] as String? ?? '');
    final descriptionController = TextEditingController();
    final debitController = TextEditingController(
      text: _formatAmountForInput((candidate?['suggested_debit'] as num?)?.toDouble()),
    );
    final creditController = TextEditingController(
      text: _formatAmountForInput((candidate?['suggested_credit'] as num?)?.toDouble()),
    );
    final balanceController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insert a transaction'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (candidate != null) ...[
                  Text(
                    'Between ${candidate['prev_date_iso'] ?? '?'} (${_formatAmount((candidate['prev_balance'] as num?)?.toDouble())}) '
                    'and ${candidate['next_date_iso'] ?? '?'} (${_formatAmount((candidate['next_balance'] as num?)?.toDouble())}) -- '
                    'unexplained gap of ${_formatAmount((candidate['gap_amount'] as num?)?.toDouble())}.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Description', isDense: true),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: debitController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Debit', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: creditController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Credit', isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Balance (optional)', isDense: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Insert')),
        ],
      ),
    );
    if (confirmed != true) {
      dateController.dispose();
      descriptionController.dispose();
      debitController.dispose();
      creditController.dispose();
      balanceController.dispose();
      return;
    }

    final description = descriptionController.text.trim();
    final dateIso = dateController.text.trim();
    final debit = double.tryParse(debitController.text.trim());
    final credit = double.tryParse(creditController.text.trim());
    final balance = double.tryParse(balanceController.text.trim());
    dateController.dispose();
    descriptionController.dispose();
    debitController.dispose();
    creditController.dispose();
    balanceController.dispose();

    if (description.isEmpty) {
      _showError('A description is required to insert a transaction.');
      return;
    }

    try {
      await ref.read(workflowControllerProvider.notifier).insertTransaction(
            dateIso: dateIso.isEmpty ? null : dateIso,
            description: description,
            debit: debit,
            credit: credit,
            balance: balance,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction inserted.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not insert transaction: $error');
    }
  }

  Future<void> _retractInsertedRow(PipelineTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retract this inserted row?'),
        content: const Text('This removes the row you inserted. It can be re-inserted later if needed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Retract'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(workflowControllerProvider.notifier).retractInsertedTransaction(transaction.sourceCellIds);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserted row retracted.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Could not retract row: $error');
    }
  }

  String _formatAmountForInput(double? value) {
    if (value == null || value == 0.0) return '';
    return value.toStringAsFixed(2);
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    try {
      await ref.read(workflowControllerProvider.notifier).verifyDocument();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document verified — template learning complete.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Verification failed: $error');
    } finally {
      if (mounted) setState(() => _verifying = false);
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

/// Surfaces review.py's provenance drill-down (POST /review/{id}/
/// transaction/ocr-source, layout-source, parser-source, compare) --
/// built server-side (Phase 6 Part H) but previously unreachable from
/// the app, since nothing ever called them.
class _SourceDialog extends StatefulWidget {
  const _SourceDialog({required this.dio, required this.documentId, required this.transaction});

  final Dio dio;
  final String documentId;
  final PipelineTransaction transaction;

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  bool _loading = true;
  String? _error;
  List<dynamic> _ocrWords = [];
  List<dynamic> _layoutElements = [];
  List<dynamic> _parserLines = [];

  String _compareField = 'description';
  Map<String, dynamic>? _compareResult;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = {'transaction_ref': widget.transaction.sourceCellIds};
      final results = await Future.wait([
        widget.dio.post('/review/${widget.documentId}/transaction/ocr-source', data: body),
        widget.dio.post('/review/${widget.documentId}/transaction/layout-source', data: body),
        widget.dio.post('/review/${widget.documentId}/transaction/parser-source', data: body),
      ]);
      setState(() {
        _ocrWords = results[0].data as List<dynamic>;
        _layoutElements = results[1].data as List<dynamic>;
        _parserLines = results[2].data as List<dynamic>;
      });
    } catch (error) {
      setState(() => _error = 'Could not load source: $error');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _compare() async {
    setState(() {
      _comparing = true;
      _compareResult = null;
    });
    try {
      final response = await widget.dio.post(
        '/review/${widget.documentId}/transaction/compare',
        data: {'transaction_ref': widget.transaction.sourceCellIds, 'field_name': _compareField},
      );
      setState(() => _compareResult = response.data as Map<String, dynamic>);
    } catch (error) {
      setState(() => _error = 'Compare failed: $error');
    } finally {
      setState(() => _comparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Value Source & History'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 12)),
                      ),
                    _sourceSection(
                      'OCR words',
                      _ocrWords.isEmpty
                          ? 'No OCR words recorded for this row.'
                          : _ocrWords
                              .map((w) => '"${w['text']}" (${((w['confidence'] as num) * 100).toStringAsFixed(0)}%)')
                              .join(', '),
                    ),
                    _sourceSection(
                      'Layout elements',
                      _layoutElements.isEmpty
                          ? 'No layout elements recorded for this row.'
                          : _layoutElements.map((e) => e['text'] ?? e['id']).join(', '),
                    ),
                    _sourceSection(
                      'Parser lines',
                      _parserLines.isEmpty ? 'No parser source recorded for this row.' : _parserLines.join('\n'),
                    ),
                    const Divider(height: 24),
                    const Text('Compare original vs. corrected',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _compareField,
                          items: const [
                            DropdownMenuItem(value: 'date_iso', child: Text('Date', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'description', child: Text('Description', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'debit', child: Text('Debit', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'credit', child: Text('Credit', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'balance', child: Text('Balance', style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) => setState(() => _compareField = v ?? _compareField),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: _comparing ? null : _compare,
                          child: Text(_comparing ? 'Comparing…' : 'Compare'),
                        ),
                      ],
                    ),
                    if (_compareResult != null) ...[
                      const SizedBox(height: 8),
                      Text('Original: ${_compareResult!['original_value'] ?? '—'}',
                          style: const TextStyle(fontSize: 12)),
                      Text('Corrected: ${_compareResult!['corrected_value'] ?? '—'}',
                          style: const TextStyle(fontSize: 12)),
                      Text('Versions: ${_compareResult!['version_count']}', style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _sourceSection(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ],
        ),
      );
}

/// Lists every balance gap GET .../missing-transaction-candidates
/// found -- each with an Insert button that hands the candidate off to
/// _ReviewScreenState._insertTransactionDialog for pre-filling -- plus
/// a standalone "insert manually" action for a row a reviewer spots by
/// eye that never showed up as a balance mismatch.
class _MissingTransactionsDialog extends StatelessWidget {
  const _MissingTransactionsDialog({
    required this.candidates,
    required this.onInsert,
    required this.onInsertManually,
  });

  final List<Map<String, dynamic>> candidates;
  final void Function(Map<String, dynamic> candidate) onInsert;
  final VoidCallback onInsertManually;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Missing transactions'),
      content: SizedBox(
        width: 420,
        child: candidates.isEmpty
            ? Text(
                'No balance gaps found -- every transaction\'s running balance reconciles with the one before it.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The running balance doesn\'t add up between these rows -- a transaction the parser '
                      'missed likely belongs in the gap. Description and exact date aren\'t recoverable here; '
                      'fill those in when you insert.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 10),
                    for (final c in candidates)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: AppColors.panel2,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${c['prev_date_iso'] ?? '?'} → ${c['next_date_iso'] ?? '?'}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Gap: ${(c['gap_amount'] as num?)?.toStringAsFixed(2) ?? '?'} '
                                      '(${(c['suggested_credit'] as num?) != null && (c['suggested_credit'] as num) > 0 ? 'likely credit' : 'likely debit'})',
                                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => onInsert(c),
                                child: const Text('Insert', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: onInsertManually, child: const Text('+ Insert Manually')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

/// Six validation-report categories (HTML feature-parity closure Phase
/// 12) -- mirrors the HTML source's VALIDATION_LABELS exactly. Sourced
/// from whichever signal already carries that information: the local
/// deterministic balance validator's warning codes (missingBalance/
/// impossibleBalance/duplicates), Gemini's own suggested-correction
/// `kind` field (debitCreditConflict), and the already-loaded
/// transaction list itself (invalidDate/ocrMistakes -- exactly what
/// the HTML computed client-side too, just against real backend data
/// here instead of a purely-local heuristic). Not a new backend
/// endpoint -- pure client-side grouping over data every one of these
/// three sources already returns.
enum _ValidationCategory { missingBalance, invalidDate, impossibleBalance, debitCreditConflict, duplicates, ocrMistakes }

const _validationCategoryLabels = {
  _ValidationCategory.missingBalance: ('🧾', 'Missing balance'),
  _ValidationCategory.invalidDate: ('📅', 'Invalid date'),
  _ValidationCategory.impossibleBalance: ('⚖️', 'Impossible balance'),
  _ValidationCategory.debitCreditConflict: ('↔️', 'Debit/Credit conflict'),
  _ValidationCategory.duplicates: ('📑', 'Possible duplicate'),
  _ValidationCategory.ocrMistakes: ('🔍', 'Possible OCR mistake'),
};

const _missingBalanceCodes = {'missing_opening_balance', 'missing_closing_balance', 'missing_transaction_balance'};
const _impossibleBalanceCodes = {'balance_does_not_reconcile', 'closing_balance_mismatch'};
const _lowConfidenceThreshold = 0.5;

Map<_ValidationCategory, List<String>> _categorizeValidationFindings({
  required List<Map<String, dynamic>> parserWarnings,
  required List<Map<String, dynamic>> typeCorrections,
  required List<PipelineTransaction> transactions,
}) {
  final buckets = {for (final c in _ValidationCategory.values) c: <String>[]};

  for (final warning in parserWarnings) {
    final code = warning['code'] as String?;
    final message = warning['message'] as String? ?? code ?? 'Unknown issue';
    if (_missingBalanceCodes.contains(code)) {
      buckets[_ValidationCategory.missingBalance]!.add(message);
    } else if (_impossibleBalanceCodes.contains(code)) {
      buckets[_ValidationCategory.impossibleBalance]!.add(message);
    } else if (code == 'possible_duplicate_transaction') {
      buckets[_ValidationCategory.duplicates]!.add(message);
    }
  }

  for (final correction in typeCorrections) {
    buckets[_ValidationCategory.debitCreditConflict]!.add(
      'Change type: ${correction['original_value']} → ${correction['suggested_value']}',
    );
  }

  for (var i = 0; i < transactions.length; i++) {
    final t = transactions[i];
    if (t.dateIso == null || t.dateIso!.isEmpty) {
      buckets[_ValidationCategory.invalidDate]!.add('Row ${i + 1}: ${t.description}');
    }
    if (t.confidence < _lowConfidenceThreshold) {
      buckets[_ValidationCategory.ocrMistakes]!.add('Row ${i + 1}: ${t.description}');
    }
  }

  return buckets;
}

/// Shows one AI Validation run's result (POST /review/{id}/validate) --
/// overall confidence, summary, the categorized 6-bucket validation
/// report (Phase 12), and every suggested correction with Apply/
/// Dismiss. Applying calls back into _ReviewScreenState (onApply) to
/// actually persist it (Gemini Stage 3/Auto-Repair); Dismiss is purely
/// local, since nothing about a suggestion is ever saved server-side
/// until Apply.
class _AIValidationDialog extends StatefulWidget {
  const _AIValidationDialog({
    required this.result,
    required this.parserWarnings,
    required this.transactions,
    required this.onApply,
  });

  final Map<String, dynamic> result;
  final List<Map<String, dynamic>> parserWarnings;
  final List<PipelineTransaction> transactions;
  final Future<bool> Function(Map<String, dynamic> correction) onApply;

  @override
  State<_AIValidationDialog> createState() => _AIValidationDialogState();
}

class _AIValidationDialogState extends State<_AIValidationDialog> {
  late List<Map<String, dynamic>> _corrections;
  final Set<int> _applying = {};
  late Map<_ValidationCategory, List<String>> _categorized;

  @override
  void initState() {
    super.initState();
    _corrections = (widget.result['corrections'] as List? ?? []).cast<Map<String, dynamic>>();
    _recategorize();
  }

  void _recategorize() {
    _categorized = _categorizeValidationFindings(
      parserWarnings: widget.parserWarnings,
      typeCorrections: _corrections.where((c) => c['kind'] == 'type').toList(),
      transactions: widget.transactions,
    );
  }

  Future<void> _apply(int index) async {
    setState(() => _applying.add(index));
    final applied = await widget.onApply(_corrections[index]);
    if (!mounted) return;
    setState(() {
      _applying.remove(index);
      if (applied) {
        _corrections.removeAt(index);
        _recategorize();
      }
    });
  }

  void _dismiss(int index) => setState(() {
        _corrections.removeAt(index);
        _recategorize();
      });

  @override
  Widget build(BuildContext context) {
    final confidence = widget.result['overall_confidence'];
    final summary = widget.result['summary'] as String? ?? '';
    final warnings = (widget.result['warnings'] as List? ?? []).cast<String>();

    return AlertDialog(
      title: const Text('AI Validation'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (confidence != null)
                Text('Gemini confidence: $confidence%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(summary, style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Warnings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.orange)),
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• $w', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ),
              ],
              const SizedBox(height: 12),
              _ValidationReportSummary(categorized: _categorized),
              const SizedBox(height: 12),
              if (_corrections.isEmpty)
                Text('No corrections suggested.', style: TextStyle(fontSize: 12, color: AppColors.muted))
              else
                for (var i = 0; i < _corrections.length; i++) _correctionCard(i),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _correctionCard(int index) {
    final c = _corrections[index];
    final busy = _applying.contains(index);
    final kind = c['kind'] as String;
    final label = kind == 'type'
        ? 'Change type: ${c['original_value']} → ${c['suggested_value']}'
        : 'Change amount: ${c['original_value']} → ${c['suggested_value']}';
    final evidence = c['evidence'] as String? ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.panel2,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                if (c['confidence'] != null)
                  Text('${c['confidence']}%', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
            if (evidence.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('"$evidence"',
                    style: TextStyle(fontSize: 11, color: AppColors.muted, fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => _dismiss(index),
                  child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: busy ? null : () => _apply(index),
                  child: busy
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Apply', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The 6-category chip summary + expandable detail list (HTML feature-
/// parity closure Phase 12) -- mirrors the HTML source's
/// renderValidationCard()/openValidationReport() combined into one
/// inline section rather than a chip-then-separate-modal, since this
/// dialog already IS the "AI Validate" modal.
class _ValidationReportSummary extends StatefulWidget {
  const _ValidationReportSummary({required this.categorized});

  final Map<_ValidationCategory, List<String>> categorized;

  @override
  State<_ValidationReportSummary> createState() => _ValidationReportSummaryState();
}

class _ValidationReportSummaryState extends State<_ValidationReportSummary> {
  _ValidationCategory? _expanded;

  @override
  Widget build(BuildContext context) {
    final nonEmpty = widget.categorized.entries.where((e) => e.value.isNotEmpty).toList();
    final total = nonEmpty.fold<int>(0, (sum, e) => sum + e.value.length);
    if (total == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Validation Report', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.heading)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in nonEmpty)
              InkWell(
                onTap: () => setState(() => _expanded = _expanded == entry.key ? null : entry.key),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _expanded == entry.key ? AppColors.accentSubtle : AppColors.panel2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${_validationCategoryLabels[entry.key]!.$1} ${_validationCategoryLabels[entry.key]!.$2} ${entry.value.length}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
          ],
        ),
        if (_expanded != null) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in widget.categorized[_expanded]!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(item, style: TextStyle(fontSize: 11.5, color: AppColors.text)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Previews an AI Recovery run's staged candidates (POST /review/{id}/
/// recover) -- summary, confidence, and every recovered row, read-only.
/// Pops `true` if the reviewer wants to proceed (the caller then shows
/// a separate, explicit "this replaces everything" confirmation before
/// actually calling acceptAIRecovery), `false`/dismissed otherwise.
/// Nothing here calls the backend -- accepting is entirely the caller's
/// responsibility, so this dialog can't itself cause data loss.
class _AIRecoveryDialog extends StatelessWidget {
  const _AIRecoveryDialog({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final confidence = result['overall_confidence'];
    final summary = result['summary'] as String? ?? '';
    final transactions = (result['transactions'] as List).cast<Map<String, dynamic>>();

    return AlertDialog(
      title: const Text('AI Recovery -- staged results'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (confidence != null)
              Text('Gemini confidence: $confidence%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(summary, style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
            const SizedBox(height: 10),
            Text('${transactions.length} transaction(s) recovered:',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final t = transactions[index];
                  final debit = t['debit'];
                  final credit = t['credit'];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(width: 80, child: Text(t['date_iso']?.toString() ?? '?', style: const TextStyle(fontSize: 11))),
                        Expanded(
                          child: Text(t['description']?.toString() ?? '',
                              style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            debit != null ? (debit as num).toStringAsFixed(2) : '',
                            style: TextStyle(fontSize: 11, color: AppColors.red),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            credit != null ? (credit as num).toStringAsFixed(2) : '',
                            style: TextStyle(fontSize: 11, color: AppColors.green),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Reject')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Review & Accept')),
      ],
    );
  }
}
