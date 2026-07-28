import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/stat_card.dart';

/// Net-new screen — no HTML precedent. Surfaces the Dataset Management
/// Module (curated regression corpus + PII anonymization + accuracy
/// dashboard) built server-side. Admin-only actions (import/anonymize/
/// verify/export/run-regression) are attempted directly; the backend
/// itself enforces the role check (require_role("admin")), so a 403
/// here just surfaces as an error banner rather than being hidden.
class DatasetManagerScreen extends ConsumerStatefulWidget {
  const DatasetManagerScreen({super.key});

  @override
  ConsumerState<DatasetManagerScreen> createState() => _DatasetManagerScreenState();
}

class _DatasetManagerScreenState extends ConsumerState<DatasetManagerScreen> {
  int _tab = 0;
  String? _status;
  bool _busy = false;

  Map<String, dynamic>? _stats;
  List<dynamic> _versions = [];

  final _bankController = TextEditingController(text: 'BAHL');
  final _versionLabelController = TextEditingController();
  final _datasetDocIdController = TextEditingController();

  bool _anonymizing = false;
  List<dynamic> _annotations = [];
  String? _documentStatus;
  Map<String, dynamic>? _groundTruthCandidate;
  bool _groundTruthEditable = false;
  final _groundTruthEditController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatistics();
    _loadVersions();
  }

  @override
  void dispose() {
    _bankController.dispose();
    _versionLabelController.dispose();
    _datasetDocIdController.dispose();
    _groundTruthEditController.dispose();
    super.dispose();
  }

  Future<void> _loadStatistics() async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/dataset-management/statistics');
      setState(() => _stats = response.data as Map<String, dynamic>);
    } catch (_) {
      // Statistics may be empty before any regression run — non-fatal.
    }
  }

  Future<void> _loadVersions() async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/dataset-management/versions');
      setState(() => _versions = response.data as List<dynamic>);
    } catch (_) {
      // No versions yet — non-fatal.
    }
  }

  Future<void> _importStatement() async {
    final picked = await FilePicker.platform.pickFiles();
    if (picked == null || picked.files.single.path == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final path = picked.files.single.path!;
      final name = picked.files.single.name;
      final data = FormData.fromMap({
        'bank_name': _bankController.text.trim(),
        'file': await MultipartFile.fromFile(path, filename: name),
      });
      final response = await dio.post('/dataset-management/import', data: data);
      final datasetDocumentId = response.data['id'].toString();
      setState(() {
        _status = 'Imported: $datasetDocumentId — switch to Annotate & Verify to continue.';
        _datasetDocIdController.text = datasetDocumentId;
        _documentStatus = response.data['status']?.toString();
      });
    } catch (error) {
      setState(() => _status = 'Import failed: $error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _anonymize() async {
    final id = _datasetDocIdController.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _anonymizing = true;
      _status = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/dataset-management/$id/anonymize');
      final jobId = response.data['job_id'].toString();
      while (true) {
        await Future.delayed(const Duration(milliseconds: 800));
        final statusResponse = await dio.get('/ocr/status/$jobId');
        final status = statusResponse.data['status'] as String;
        if (status == 'succeeded') break;
        if (status == 'failed') {
          throw Exception(statusResponse.data['error_message'] ?? 'Anonymization job failed');
        }
      }
      setState(() => _status = 'Anonymization complete — load PII regions below.');
      await _loadAnnotations();
    } catch (error) {
      setState(() => _status = 'Anonymize failed: $error');
    } finally {
      setState(() => _anonymizing = false);
    }
  }

  Future<void> _loadAnnotations() async {
    final id = _datasetDocIdController.text.trim();
    if (id.isEmpty) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/dataset-management/$id/pii-annotations');
      setState(() => _annotations = response.data as List<dynamic>);
    } catch (error) {
      setState(() => _status = 'Could not load PII regions: $error');
    }
  }

  Future<void> _reviewAnnotation(String annotationId, String action) async {
    final id = _datasetDocIdController.text.trim();
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.post('/dataset-management/$id/pii-annotations/$annotationId/$action');
      await _loadAnnotations();
    } catch (error) {
      setState(() => _status = '${action[0].toUpperCase()}${action.substring(1)} failed: $error');
    }
  }

  Future<void> _completeVerification() async {
    final id = _datasetDocIdController.text.trim();
    if (id.isEmpty) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/dataset-management/$id/complete-verification');
      setState(() {
        _documentStatus = response.data['status']?.toString();
        _status = 'Verification complete — unredacted original deleted, redacted pages are now the record.';
      });
    } catch (error) {
      setState(() => _status = 'Complete verification failed: $error');
    }
  }

  Future<void> _generateGroundTruth() async {
    final id = _datasetDocIdController.text.trim();
    if (id.isEmpty) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/dataset-management/$id/ground-truth/generate');
      final candidate = response.data['expected_json'] as Map<String, dynamic>;
      setState(() {
        _groundTruthCandidate = candidate;
        _groundTruthEditController.text = const JsonEncoder.withIndent('  ').convert(candidate);
        _groundTruthEditable = false;
        _status = 'Ground truth candidate generated from the pipeline\'s current output — review, then approve.';
      });
    } catch (error) {
      setState(() => _status = 'Ground truth generation failed: $error');
    }
  }

  Future<void> _approveGroundTruth() async {
    final id = _datasetDocIdController.text.trim();
    if (id.isEmpty || _groundTruthCandidate == null) return;
    try {
      Map<String, dynamic> expectedJson;
      try {
        expectedJson = jsonDecode(_groundTruthEditController.text) as Map<String, dynamic>;
      } catch (_) {
        setState(() => _status = 'Ground truth JSON is invalid — fix it before approving.');
        return;
      }
      final dio = ref.read(apiClientProvider).dio;
      await dio.post('/dataset-management/$id/ground-truth/approve', data: {'expected_json': expectedJson});
      setState(() {
        _status = 'Ground truth approved (version persisted) — document is now active in the corpus.';
        _groundTruthCandidate = null;
      });
    } catch (error) {
      setState(() => _status = 'Ground truth approval failed: $error');
    }
  }

  Future<void> _createVersion() async {
    final label = _versionLabelController.text.trim();
    if (label.isEmpty) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.post('/dataset-management/versions', data: {'version_label': label, 'description': null});
      _versionLabelController.clear();
      await _loadVersions();
    } catch (error) {
      setState(() => _status = 'Version snapshot failed: $error');
    }
  }

  Future<void> _runRegression() async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.post('/dataset-management/run-regression', data: {'dataset_version_id': null});
      setState(() => _status = 'Regression run started (job ${response.data['job_id']}).');
    } catch (error) {
      setState(() => _status = 'Regression run failed: $error');
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
                    icon: '🗂️',
                    title: 'Dataset Manager',
                    subtitle: 'Curated regression corpus, PII anonymization, and accuracy dashboard.',
                  ),
                  Row(
                    children: [
                      _tabButton('Import', 0),
                      _tabButton('Annotate & Verify', 1),
                      _tabButton('Statistics', 2),
                      _tabButton('Versions & Regression', 3),
                    ],
                  ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppAlert(kind: AppAlertKind.info, message: _status!),
                    ),
                ],
              ),
            ),
            if (_tab == 0) _importTab(),
            if (_tab == 1) _annotateTab(),
            if (_tab == 2) _statisticsTab(),
            if (_tab == 3) _versionsTab(),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final active = _tab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton(
        onPressed: () => setState(() => _tab = index),
        style: OutlinedButton.styleFrom(
          backgroundColor: active ? AppColors.accentSubtle : AppColors.panel2,
          foregroundColor: active ? AppColors.accent : AppColors.text,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  Widget _importTab() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Import a raw statement into the curated corpus',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.heading)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bankController,
                  decoration: const InputDecoration(hintText: 'Bank name'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: _busy ? null : _importStatement, child: const Text('Choose File & Import')),
            ],
          ),
          const SizedBox(height: 10),
          if (_datasetDocIdController.text.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => setState(() => _tab = 1),
                child: const Text('Continue to Annotate & Verify →'),
              ),
            )
          else
            const AppAlert(
              kind: AppAlertKind.info,
              message: 'After importing, move to the Annotate & Verify tab to anonymize, confirm PII regions, '
                  'complete verification, and approve ground truth for this statement.',
            ),
        ],
      ),
    );
  }

  Widget _annotateTab() {
    final id = _datasetDocIdController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('1. Dataset document',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.heading)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _datasetDocIdController,
                      decoration: const InputDecoration(hintText: 'Dataset document ID (from Import)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _anonymizing || id.isEmpty ? null : _anonymize,
                    child: Text(_anonymizing ? 'Anonymizing…' : '2. Anonymize (OCR + PII detection)'),
                  ),
                ],
              ),
              if (_documentStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Status: $_documentStatus', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                  const Text('3. Review detected PII regions',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.heading)),
                  OutlinedButton(onPressed: id.isEmpty ? null : _loadAnnotations, child: const Text('Reload')),
                ],
              ),
              const SizedBox(height: 8),
              if (_annotations.isEmpty)
                Text('No PII regions loaded yet — anonymize first.', style: TextStyle(color: AppColors.muted))
              else
                for (final a in _annotations)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${a['pii_type']} · page ${a['page_number']} · confidence '
                            '${a['confidence'] != null ? (a['confidence'] as num).toStringAsFixed(2) : '—'} · '
                            '${a['review_status']}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _reviewAnnotation(a['id'].toString(), 'confirm'),
                          child: const Text('Confirm', style: TextStyle(color: AppColors.green)),
                        ),
                        TextButton(
                          onPressed: () => _reviewAnnotation(a['id'].toString(), 'reject'),
                          child: const Text('Reject', style: TextStyle(color: AppColors.red)),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 10),
              AppAlert(
                kind: AppAlertKind.warn,
                message: 'Completing verification permanently deletes the unredacted original — the redacted '
                    'pages become the permanent record. Only do this once every region above is confirmed or '
                    'rejected correctly.',
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: id.isEmpty ? null : _completeVerification,
                child: const Text('4. Complete Verification'),
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('5. Ground truth',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.heading)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: id.isEmpty ? null : _generateGroundTruth,
                    child: const Text('Generate candidate from current pipeline output'),
                  ),
                  const SizedBox(width: 10),
                  if (_groundTruthCandidate != null)
                    OutlinedButton(
                      onPressed: () => setState(() => _groundTruthEditable = !_groundTruthEditable),
                      child: Text(_groundTruthEditable ? 'Preview' : 'Edit before approving'),
                    ),
                ],
              ),
              if (_groundTruthCandidate != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.gray, borderRadius: BorderRadius.circular(6)),
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: TextField(
                      controller: _groundTruthEditController,
                      readOnly: !_groundTruthEditable,
                      maxLines: null,
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.text),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _approveGroundTruth,
                  child: const Text('Approve — persist version, mark document active'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statisticsTab() {
    final stats = _stats;
    if (stats == null) {
      return AppCard(
        child: AppAlert(kind: AppAlertKind.info, message: 'No regression statistics yet — run a regression first.'),
      );
    }
    final accuracy = stats['latest_run_accuracy'];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                  width: 220,
                  child: StatCard(label: 'Active Documents', value: '${stats['total_active_documents'] ?? 0}')),
              SizedBox(
                  width: 220,
                  child: StatCard(
                      label: 'Latest Run Accuracy',
                      value: accuracy == null ? '—' : '${(accuracy * 100).toStringAsFixed(1)}%')),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Most Common Field Mismatches',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
          const SizedBox(height: 8),
          for (final entry in (stats['most_common_field_mismatches'] as List<dynamic>? ?? []))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('${entry['field'] ?? entry}', style: TextStyle(fontSize: 12.5, color: AppColors.text)),
            ),
        ],
      ),
    );
  }

  Widget _versionsTab() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _versionLabelController,
                  decoration: const InputDecoration(hintText: 'New version label, e.g. v1'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: _createVersion, child: const Text('Snapshot Corpus')),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: _runRegression, child: const Text('Run Regression')),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Versions', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
          const SizedBox(height: 8),
          for (final v in _versions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${v['version_label']} — ${v['document_count']} documents',
                  style: TextStyle(fontSize: 12.5, color: AppColors.text)),
            ),
          if (_versions.isEmpty) Text('No versions snapshotted yet.', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
