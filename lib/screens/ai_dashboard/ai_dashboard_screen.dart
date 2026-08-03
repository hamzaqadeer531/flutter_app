import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/stat_card.dart';

/// AI usage/cost dashboard (HTML feature-parity closure Phase 11) --
/// GET /ai-usage/dashboard for the read-only totals, GET|PUT /settings/
/// gemini-pricing for admin-editable per-model pricing. Both endpoints
/// are admin-only server-side; this screen assumes the caller already
/// is one (same convention as the Administration screen).
class AiDashboardScreen extends ConsumerStatefulWidget {
  const AiDashboardScreen({super.key});

  @override
  ConsumerState<AiDashboardScreen> createState() => _AiDashboardScreenState();
}

class _AiDashboardScreenState extends ConsumerState<AiDashboardScreen> {
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic> _pricing = {};
  bool _loading = true;
  String? _error;

  final _newModelController = TextEditingController();
  final Map<String, TextEditingController> _inputControllers = {};
  final Map<String, TextEditingController> _outputControllers = {};
  bool _saving = false;
  String? _saveStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newModelController.dispose();
    for (final c in _inputControllers.values) {
      c.dispose();
    }
    for (final c in _outputControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        dio.get('/ai-usage/dashboard'),
        dio.get('/settings/gemini-pricing'),
      ]);
      final pricing = (results[1].data['pricing'] as Map<String, dynamic>? ?? {});
      setState(() {
        _dashboard = results[0].data as Map<String, dynamic>;
        _pricing = pricing;
        _loading = false;
      });
      _syncPricingControllers();
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Could not load AI usage dashboard: $error';
      });
    }
  }

  void _syncPricingControllers() {
    for (final entry in _pricing.entries) {
      final values = entry.value as Map<String, dynamic>;
      _inputControllers.putIfAbsent(entry.key, () => TextEditingController()).text = '${values['input'] ?? 0.0}';
      _outputControllers.putIfAbsent(entry.key, () => TextEditingController()).text = '${values['output'] ?? 0.0}';
    }
  }

  void _addModelRow() {
    final model = _newModelController.text.trim();
    if (model.isEmpty || _pricing.containsKey(model)) return;
    setState(() {
      _pricing = {..._pricing, model: {'input': 0.0, 'output': 0.0}};
      _newModelController.clear();
    });
    _syncPricingControllers();
  }

  Future<void> _savePricing() async {
    setState(() {
      _saving = true;
      _saveStatus = null;
    });
    try {
      final pricing = <String, dynamic>{
        for (final model in _pricing.keys)
          model: {
            'input': double.tryParse(_inputControllers[model]?.text ?? '0') ?? 0.0,
            'output': double.tryParse(_outputControllers[model]?.text ?? '0') ?? 0.0,
          },
      };
      final dio = ref.read(apiClientProvider).dio;
      await dio.put('/settings/gemini-pricing', data: {'pricing': pricing});
      setState(() => _saveStatus = 'Pricing saved.');
      await _load();
    } catch (error) {
      setState(() => _saveStatus = 'Could not save pricing: $error');
    } finally {
      setState(() => _saving = false);
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
                    icon: '🤖',
                    title: 'AI Usage & Cost',
                    subtitle: 'Gemini calls, tokens, and estimated cost across every AI-backed feature.',
                  ),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.accent)))
                  else if (_error != null)
                    AppAlert(kind: AppAlertKind.error, message: _error!)
                  else if (_dashboard != null)
                    _DashboardSummary(dashboard: _dashboard!),
                ],
              ),
            ),
            if (!_loading && _dashboard != null)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppCardHeader(
                      icon: '💲',
                      title: 'Gemini Pricing',
                      subtitle: 'USD per 1,000 tokens, used to estimate cost for future calls.',
                    ),
                    for (final model in _pricing.keys)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(flex: 2, child: Text(model, style: const TextStyle(fontSize: 12.5, color: AppColors.text))),
                            Expanded(
                              child: TextField(
                                controller: _inputControllers[model],
                                decoration: const InputDecoration(labelText: 'Input / 1K'),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _outputControllers[model],
                                decoration: const InputDecoration(labelText: 'Output / 1K'),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newModelController,
                            decoration: const InputDecoration(hintText: 'Add model (e.g. gemini-3.5-flash)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(onPressed: _addModelRow, child: const Text('Add')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _saving ? null : _savePricing,
                      child: Text(_saving ? 'Saving…' : 'Save Pricing'),
                    ),
                    if (_saveStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: AppAlert(kind: AppAlertKind.info, message: _saveStatus!),
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

class _DashboardSummary extends StatelessWidget {
  const _DashboardSummary({required this.dashboard});

  final Map<String, dynamic> dashboard;

  @override
  Widget build(BuildContext context) {
    final byFeature = (dashboard['by_feature'] as Map<String, dynamic>? ?? {});
    final byModel = (dashboard['by_model'] as Map<String, dynamic>? ?? {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(width: 200, child: StatCard(label: 'Total Calls', value: '${dashboard['total_calls']}')),
            SizedBox(width: 200, child: StatCard(label: 'Total Tokens', value: '${dashboard['total_tokens']}')),
            SizedBox(
              width: 200,
              child: StatCard(
                label: 'Estimated Cost',
                value: '\$${(dashboard['total_cost_usd'] as num).toStringAsFixed(4)}',
                valueColor: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (byFeature.isNotEmpty) ...[
          Text('By Feature', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
          const SizedBox(height: 6),
          for (final entry in byFeature.entries) _UsageRow(label: entry.key, bucket: entry.value as Map<String, dynamic>),
          const SizedBox(height: 12),
        ],
        if (byModel.isNotEmpty) ...[
          Text('By Model', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.heading)),
          const SizedBox(height: 6),
          for (final entry in byModel.entries) _UsageRow(label: entry.key, bucket: entry.value as Map<String, dynamic>),
        ],
        if (byFeature.isEmpty && byModel.isEmpty)
          Text('No AI calls recorded yet.', style: TextStyle(color: AppColors.muted)),
      ],
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.label, required this.bucket});

  final String label;
  final Map<String, dynamic> bucket;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.text))),
          Text('${bucket['calls']} calls', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(width: 10),
          Text('${bucket['tokens']} tokens', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(width: 10),
          Text('\$${(bucket['cost_usd'] as num).toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accent)),
        ],
      ),
    );
  }
}
