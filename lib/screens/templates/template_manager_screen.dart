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
///
/// Honest gap: the backend has get/rename/clone/activate/deactivate/
/// archive/delete/export/import/rollback for a template BY ID, but no
/// "list all templates" endpoint yet — so this is a lookup-by-ID
/// workspace rather than a browsable table. Adding a list endpoint is a
/// small, backward-compatible follow-up, not done here to avoid
/// expanding backend scope without a specific ask.
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

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
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
      setState(() => _template = response.data as Map<String, dynamic>);
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
    } catch (error) {
      setState(() => _error = 'Action failed: $error');
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
        _idController.clear();
      });
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
                    subtitle: 'Look up a saved layout template by ID to inspect or manage it.',
                  ),
                  const AppAlert(
                    kind: AppAlertKind.info,
                    message:
                        'The backend does not yet expose a "list all templates" endpoint — templates are looked up by '
                        'the ID recorded when they were saved during Training Mode.',
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
                        OutlinedButton(onPressed: () => _action('clone'), child: const Text('Clone')),
                        OutlinedButton(
                          onPressed: _delete,
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
