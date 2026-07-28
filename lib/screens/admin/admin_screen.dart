import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';

/// Net-new screen — no HTML precedent. The backend has no
/// organizations/users CRUD API (Phase 6 Part L added org SCOPING to
/// existing resources, not an org-management surface), so this screen
/// is deliberately scoped to what genuinely exists today: license
/// issue/list/revoke by organization ID (Phase 7 Part J) and the audit
/// trail lookup by document ID (Phase 6 Part K). Building a fabricated
/// user/org management UI backed by nothing would be worse than being
/// honest about the gap.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  int _tab = 0;
  final _orgIdController = TextEditingController();
  final _documentIdController = TextEditingController();
  List<dynamic> _licenses = [];
  List<dynamic> _auditEntries = [];
  String? _error;

  @override
  void dispose() {
    _orgIdController.dispose();
    _documentIdController.dispose();
    super.dispose();
  }

  Future<void> _loadLicenses() async {
    final orgId = _orgIdController.text.trim();
    if (orgId.isEmpty) return;
    setState(() => _error = null);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/licenses/organization/$orgId');
      setState(() => _licenses = response.data as List<dynamic>);
    } catch (error) {
      setState(() => _error = 'Could not load licenses: $error');
    }
  }

  Future<void> _revoke(String licenseId) async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.post('/licenses/$licenseId/revoke');
      await _loadLicenses();
    } catch (error) {
      setState(() => _error = 'Revoke failed: $error');
    }
  }

  Future<void> _loadAudit() async {
    final documentId = _documentIdController.text.trim();
    if (documentId.isEmpty) return;
    setState(() => _error = null);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/audit/$documentId');
      setState(() => _auditEntries = response.data as List<dynamic>);
    } catch (error) {
      setState(() => _error = 'Could not load audit trail: $error');
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
                    icon: '🛡️',
                    title: 'Administration',
                    subtitle: 'License management and audit trail lookup.',
                  ),
                  Row(
                    children: [
                      _tabButton('Licenses', 0),
                      _tabButton('Audit Trail', 1),
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
            if (_tab == 0) _licensesTab(),
            if (_tab == 1) _auditTab(),
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

  Widget _licensesTab() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orgIdController,
                  decoration: const InputDecoration(hintText: 'Organization ID (UUID)'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: _loadLicenses, child: const Text('Load Licenses')),
            ],
          ),
          const SizedBox(height: 16),
          for (final license in _licenses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${license['tier']} · expires ${license['expires_at']} · ${license['status']}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _revoke(license['id'].toString()),
                    child: const Text('Revoke', style: TextStyle(color: AppColors.red)),
                  ),
                ],
              ),
            ),
          if (_licenses.isEmpty) Text('No licenses loaded.', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _auditTab() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _documentIdController,
                  decoration: const InputDecoration(hintText: 'Document ID (UUID)'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: _loadAudit, child: const Text('Load Trail')),
            ],
          ),
          const SizedBox(height: 16),
          for (final entry in _auditEntries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '${entry['created_at']} — ${entry['action']} by ${entry['user_id']}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.text),
              ),
            ),
          if (_auditEntries.isEmpty) Text('No audit entries loaded.', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
