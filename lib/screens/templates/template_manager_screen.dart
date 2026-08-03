import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';

/// Migration of the HTML source's Templates Library modal, wired to the
/// real Template Library API (Phase 5 Part D) instead of localStorage.
/// Now browsable via GET /templates -- previously templates could only
/// be looked up by an ID a caller already had memorized.
class TemplateManagerScreen extends ConsumerStatefulWidget {
  const TemplateManagerScreen({super.key});

  @override
  ConsumerState<TemplateManagerScreen> createState() => _TemplateManagerScreenState();
}

class _TemplateManagerScreenState extends ConsumerState<TemplateManagerScreen> {
  final _idController = TextEditingController();
  Map<String, dynamic>? _template;
  String? _error;
  bool _loading = false;
  List<dynamic>? _lineage;

  List<dynamic> _templates = [];
  bool _loadingList = false;
  bool _includeArchived = false;

  // Template Debug Mode (HTML feature-parity closure Phase 10).
  final _debugDocumentIdController = TextEditingController();
  List<dynamic>? _debugResults;
  bool _debugLoading = false;
  String? _debugError;

  // Training Mode (HTML feature-parity closure Phase 10) -- a manual
  // column mapping keyed by the document's own already-detected layout
  // column INDEX (visible via the Debug Match / parsed-document view),
  // not a visual drag-and-drop picker -- a smaller, honest first cut
  // rather than a slower, more polished column-highlighter UI.
  final _trainDocumentIdController = TextEditingController();
  final _trainNameController = TextEditingController();
  final _trainDateController = TextEditingController();
  final _trainDescriptionController = TextEditingController();
  final _trainDebitController = TextEditingController();
  final _trainCreditController = TextEditingController();
  final _trainBalanceController = TextEditingController();
  bool _trainLoading = false;
  String? _trainStatus;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _idController.dispose();
    _debugDocumentIdController.dispose();
    _trainDocumentIdController.dispose();
    _trainNameController.dispose();
    _trainDateController.dispose();
    _trainDescriptionController.dispose();
    _trainDebitController.dispose();
    _trainCreditController.dispose();
    _trainBalanceController.dispose();
    super.dispose();
  }

  Future<void> _debugMatch() async {
    final documentId = _debugDocumentIdController.text.trim();
    if (documentId.isEmpty) return;
    setState(() {
      _debugLoading = true;
      _debugError = null;
      _debugResults = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/templates/debug-match/$documentId');
      setState(() => _debugResults = response.data as List<dynamic>);
    } catch (error) {
      setState(() => _debugError = 'Could not debug-match: $error');
    } finally {
      setState(() => _debugLoading = false);
    }
  }

  Future<void> _saveTemplateFromMapping() async {
    final documentId = _trainDocumentIdController.text.trim();
    final name = _trainNameController.text.trim();
    if (documentId.isEmpty || name.isEmpty) {
      setState(() => _trainStatus = 'Document ID and a template name are both required.');
      return;
    }
    final columnMapping = <String, int>{};
    for (final (field, controller) in [
      ('date', _trainDateController),
      ('description', _trainDescriptionController),
      ('debit', _trainDebitController),
      ('credit', _trainCreditController),
      ('balance', _trainBalanceController),
    ]) {
      final text = controller.text.trim();
      if (text.isEmpty) continue;
      final index = int.tryParse(text);
      if (index == null) {
        setState(() => _trainStatus = 'Column index for "$field" must be a whole number.');
        return;
      }
      columnMapping[field] = index;
    }
    if (columnMapping.isEmpty) {
      setState(() => _trainStatus = 'Map at least one column before saving.');
      return;
    }

    setState(() {
      _trainLoading = true;
      _trainStatus = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.post('/templates/from-mapping', data: {
        'document_id': documentId,
        'name': name,
        'column_mapping': columnMapping,
      });
      setState(() => _trainStatus = 'Template "$name" saved -- future matching documents will parse using this mapping.');
      await _loadTemplates();
    } catch (error) {
      setState(() => _trainStatus = 'Could not save template: $error');
    } finally {
      setState(() => _trainLoading = false);
    }
  }

  Future<void> _loadTemplates() async {
    setState(() => _loadingList = true);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/templates', queryParameters: {'include_archived': _includeArchived});
      setState(() => _templates = response.data as List<dynamic>);
    } catch (error) {
      setState(() => _error = 'Could not load templates: $error');
    } finally {
      setState(() => _loadingList = false);
    }
  }

  void _selectFromList(Map<String, dynamic> template) {
    setState(() {
      _template = template;
      _idController.text = template['id'].toString();
      _lineage = null;
      _error = null;
    });
  }

  Future<void> _lookup() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/templates/$id');
      setState(() {
        _template = response.data as Map<String, dynamic>;
        _lineage = null;
      });
    } catch (error) {
      setState(() {
        _error = 'Template not found or could not be loaded.';
        _template = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _action(String path) async {
    final id = _template?['id'];
    if (id == null) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/templates/$id/$path');
      setState(() => _template = response.data as Map<String, dynamic>);
      await _loadTemplates();
    } catch (error) {
      setState(() => _error = 'Action failed: $error');
    }
  }

  Future<String?> _promptForName(String title, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final id = _template?['id'];
    if (id == null) return;
    final newName = await _promptForName('Rename template', 'New name');
    if (newName == null || newName.isEmpty) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/templates/$id/rename', data: {'new_name': newName});
      setState(() => _template = response.data as Map<String, dynamic>);
      await _loadTemplates();
    } catch (error) {
      setState(() => _error = 'Rename failed: $error');
    }
  }

  /// Fixes a pre-existing bug: this previously called _action('clone')
  /// with no request body, but POST /templates/{id}/clone requires
  /// {new_name} -- every clone attempt would 422.
  Future<void> _clone() async {
    final id = _template?['id'];
    if (id == null) return;
    final newName = await _promptForName('Clone template', 'Name for the clone');
    if (newName == null || newName.isEmpty) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/templates/$id/clone', data: {'new_name': newName});
      setState(() => _template = response.data as Map<String, dynamic>);
      await _loadTemplates();
    } catch (error) {
      setState(() => _error = 'Clone failed: $error');
    }
  }

  Future<void> _exportTemplate() async {
    final id = _template?['id'];
    if (id == null) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/templates/$id/export');
      final bundle = response.data['bundle'];
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save template bundle',
        fileName: 'template_${_template!['name']}_v${_template!['version']}.json',
      );
      if (savePath == null) return;
      await File(savePath).writeAsString(const JsonEncoder.withIndent('  ').convert(bundle));
      setState(() => _error = null);
    } catch (error) {
      setState(() => _error = 'Export failed: $error');
    }
  }

  Future<void> _importTemplate() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final bundle = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/templates/import', data: {'bundle': bundle});
      setState(() {
        _template = response.data as Map<String, dynamic>;
        _idController.text = _template!['id'].toString();
        _lineage = null;
        _error = null;
      });
      await _loadTemplates();
    } catch (error) {
      setState(() => _error = 'Import failed: $error');
    }
  }

  Future<void> _loadLineage() async {
    final lineageId = _template?['lineage_id'];
    if (lineageId == null) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/templates/lineage/$lineageId');
      setState(() => _lineage = response.data as List<dynamic>);
    } catch (error) {
      setState(() => _error = 'Could not load lineage: $error');
    }
  }

  Future<void> _rollback(int targetVersion) async {
    final lineageId = _template?['lineage_id'];
    if (lineageId == null) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response =
          await dio.post('/templates/lineage/$lineageId/rollback', data: {'target_version': targetVersion});
      setState(() {
        _template = response.data as Map<String, dynamic>;
        _lineage = null;
      });
      await _loadTemplates();
    } catch (error) {
      setState(() => _error = 'Rollback failed: $error');
    }
  }

  Future<void> _delete() async {
    final id = _template?['id'];
    if (id == null) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.delete('/templates/$id');
      setState(() {
        _template = null;
        _lineage = null;
        _idController.clear();
      });
      await _loadTemplates();
    } catch (error) {
      setState(() => _error = 'Delete failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      body: AppMain(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppCardHeader(
                    icon: '🧩',
                    title: 'Template Manager',
                    subtitle: 'Browse saved layout templates, or look one up directly by ID.',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _idController,
                          decoration: const InputDecoration(hintText: 'Template ID (UUID)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(onPressed: _loading ? null : _lookup, child: const Text('Look Up')),
                      const SizedBox(width: 10),
                      OutlinedButton(onPressed: _importTemplate, child: const Text('Import from File')),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppAlert(kind: AppAlertKind.error, message: _error!),
                    ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppCardHeader(
                    icon: '🔍',
                    title: 'Debug Match',
                    subtitle: 'See every active template\'s score against a document, not just the winner.',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _debugDocumentIdController,
                          decoration: const InputDecoration(hintText: 'Document ID (UUID)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _debugLoading ? null : _debugMatch,
                        child: Text(_debugLoading ? 'Checking…' : 'Debug Match'),
                      ),
                    ],
                  ),
                  if (_debugError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppAlert(kind: AppAlertKind.error, message: _debugError!),
                    ),
                  if (_debugResults != null) ...[
                    const SizedBox(height: 12),
                    if (_debugResults!.isEmpty)
                      Text('No active templates for this document\'s type.', style: TextStyle(color: AppColors.muted))
                    else
                      for (final r in _debugResults!)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${r['template_id']} · v${r['version']} · ${r['scope']}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.text)),
                              ),
                              Text('${(r['score'] as num).toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.accent)),
                            ],
                          ),
                        ),
                  ],
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppCardHeader(
                    icon: '🎓',
                    title: 'Training Mode',
                    subtitle: 'Manually map a document\'s detected columns to fields and save as a template -- '
                        'future documents matching it will actually be parsed using this mapping.',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _trainDocumentIdController,
                          decoration: const InputDecoration(hintText: 'Source document ID (UUID)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _trainNameController,
                          decoration: const InputDecoration(hintText: 'Template name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(width: 130, child: TextField(controller: _trainDateController, decoration: const InputDecoration(labelText: 'Date col #'))),
                      SizedBox(width: 130, child: TextField(controller: _trainDescriptionController, decoration: const InputDecoration(labelText: 'Description col #'))),
                      SizedBox(width: 130, child: TextField(controller: _trainDebitController, decoration: const InputDecoration(labelText: 'Debit col #'))),
                      SizedBox(width: 130, child: TextField(controller: _trainCreditController, decoration: const InputDecoration(labelText: 'Credit col #'))),
                      SizedBox(width: 130, child: TextField(controller: _trainBalanceController, decoration: const InputDecoration(labelText: 'Balance col #'))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _trainLoading ? null : _saveTemplateFromMapping,
                    child: Text(_trainLoading ? 'Saving…' : 'Save as Template'),
                  ),
                  if (_trainStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppAlert(kind: AppAlertKind.info, message: _trainStatus!),
                    ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('All Templates',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.heading)),
                      Row(
                        children: [
                          Checkbox(
                            value: _includeArchived,
                            onChanged: (checked) {
                              setState(() => _includeArchived = checked ?? false);
                              _loadTemplates();
                            },
                          ),
                          Text('Show archived', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _loadingList ? null : _loadTemplates,
                            child: Text(_loadingList ? 'Loading…' : 'Reload'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_templates.isEmpty)
                    Text('No templates yet.', style: TextStyle(color: AppColors.muted))
                  else
                    for (final t in _templates)
                      InkWell(
                        onTap: () => _selectFromList(t as Map<String, dynamic>),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${t['name']} · v${t['version']}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: _template != null && _template!['id'] == t['id']
                                        ? AppColors.accent
                                        : AppColors.text,
                                    fontWeight:
                                        _template != null && _template!['id'] == t['id'] ? FontWeight.w700 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              Text(
                                '${t['is_active'] == true ? 'Active' : 'Inactive'}'
                                '${t['is_archived'] == true ? ' · Archived' : ''}',
                                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
            if (_template != null)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_template!['name']?.toString() ?? 'Untitled template',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.heading)),
                    const SizedBox(height: 4),
                    Text(
                      'Version ${_template!['version']} · ${_template!['is_active'] == true ? 'Active' : 'Inactive'}'
                      '${_template!['is_archived'] == true ? ' · Archived' : ''}',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(onPressed: () => _action('activate'), child: const Text('Activate')),
                        OutlinedButton(onPressed: () => _action('deactivate'), child: const Text('Deactivate')),
                        OutlinedButton(onPressed: () => _action('archive'), child: const Text('Archive')),
                        OutlinedButton(onPressed: _rename, child: const Text('Rename')),
                        OutlinedButton(onPressed: _clone, child: const Text('Clone')),
                        OutlinedButton(onPressed: _exportTemplate, child: const Text('Export')),
                        OutlinedButton(onPressed: _loadLineage, child: const Text('View Lineage')),
                        OutlinedButton(
                          onPressed: _delete,
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                    if (_lineage != null) ...[
                      const SizedBox(height: 16),
                      const Text('Lineage (rollback to any prior version)',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
                      const SizedBox(height: 8),
                      for (final v in _lineage!)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'v${v['version']} · ${v['is_active'] == true ? 'active' : 'inactive'}'
                                  '${v['id'] == _template!['id'] ? ' (current)' : ''}',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                                ),
                              ),
                              if (v['id'] != _template!['id'])
                                TextButton(
                                  onPressed: () => _rollback(v['version'] as int),
                                  child: const Text('Roll back to this version'),
                                ),
                            ],
                          ),
                        ),
                      if (_lineage!.isEmpty)
                        Text('No lineage history found.', style: TextStyle(color: AppColors.muted)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
