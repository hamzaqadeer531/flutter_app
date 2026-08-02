import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';

/// Pixel-accurate migration of the HTML source's Settings modal —
/// rendered as a full screen here rather than a modal, matching this
/// app's screen-per-route navigation instead of the HTML wizard's
/// overlay modals. Every toggle name/default matches the HTML's
/// `SETTINGS` JS object exactly.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

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
                    icon: '⚙️',
                    title: 'Settings',
                    subtitle: 'Processing preferences — stored locally on this device.',
                  ),
                  _toggle('Template Learning', 'Master switch for the whole template engine.',
                      settings.templateLearning, (v) => controller.update((s) => s.copyWith(templateLearning: v))),
                  _toggle('Use Templates First', 'Try a saved template before bank-specific/generic parsers.',
                      settings.useTemplatesFirst, (v) => controller.update((s) => s.copyWith(useTemplatesFirst: v))),
                  _toggle('Auto-Save Template', 'Silently save a template after a successful column mapping.',
                      settings.autoSaveTemplate, (v) => controller.update((s) => s.copyWith(autoSaveTemplate: v))),
                  _toggle('OCR Cache', 'Skip re-OCR/re-parse on a previously-seen file.', settings.ocrCache,
                      (v) => controller.update((s) => s.copyWith(ocrCache: v))),
                  _toggle('AI Detection', 'Heuristic bank/account-type/statement-type auto-detection.',
                      settings.aiDetection, (v) => controller.update((s) => s.copyWith(aiDetection: v))),
                  _toggle('Image Enhancement', 'Deskew/shadow-removal/sharpen before OCR.', settings.imageEnhancement,
                      (v) => controller.update((s) => s.copyWith(imageEnhancement: v))),
                  _toggle('Multi-Pass OCR', 'Retry with an alternate mode when confidence is low.',
                      settings.multiPassOcr, (v) => controller.update((s) => s.copyWith(multiPassOcr: v))),
                  _toggle('Confidence Highlight', 'Highlight low-confidence OCR rows in Review.',
                      settings.confidenceHighlight, (v) => controller.update((s) => s.copyWith(confidenceHighlight: v))),
                  _toggle('Learning Mode', 'Capture manual corrections to improve templates over time.',
                      settings.learningMode, (v) => controller.update((s) => s.copyWith(learningMode: v))),
                  _toggle('Correction Learning', 'Store every manual correction as feedback.',
                      settings.correctionLearning, (v) => controller.update((s) => s.copyWith(correctionLearning: v))),
                  _toggle(
                      'Auto-Apply Learned Corrections',
                      'Auto-apply a correction pattern once confirmed 2+ times.',
                      settings.autoApplyLearnedCorrections,
                      (v) => controller.update((s) => s.copyWith(autoApplyLearnedCorrections: v))),
                  _toggle('Automatic Validation', 'Auto-check every extraction before Review.',
                      settings.automaticValidation, (v) => controller.update((s) => s.copyWith(automaticValidation: v))),
                  const SizedBox(height: 6),
                  Text('CONFIDENCE THRESHOLD: ${settings.confidenceThreshold.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
                  Slider(
                    value: settings.confidenceThreshold,
                    min: 0,
                    max: 100,
                    activeColor: AppColors.accent,
                    onChanged: (v) => controller.update((s) => s.copyWith(confidenceThreshold: v)),
                  ),
                ],
              ),
            ),
            // Standalone Windows desktop build only (Phase 9) -- the
            // hosted/web build configures Gemini via the backend's own
            // env vars (config.py), set by whoever runs the server, so
            // this card would be meaningless (and the backing endpoint
            // 400s) there. Same `!kIsWeb && Platform.isWindows` gate
            // app_router.dart/auth_state.dart already use.
            if (!kIsWeb && Platform.isWindows) ...[
              const SizedBox(height: 16),
              const _GeminiKeyCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
                Text(subtitle, style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
          Switch(value: value, activeThumbColor: AppColors.accent, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _GeminiKeyCard extends ConsumerStatefulWidget {
  const _GeminiKeyCard();

  @override
  ConsumerState<_GeminiKeyCard> createState() => _GeminiKeyCardState();
}

class _GeminiKeyCardState extends ConsumerState<_GeminiKeyCard> {
  final _apiKeyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _configured = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/settings/gemini-key');
      final body = response.data as Map<String, dynamic>;
      setState(() {
        _enabled = body['enabled'] as bool;
        _configured = body['configured'] as bool;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = 'Could not load Gemini status: $error');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save({String? apiKey, required bool enabled}) async {
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final requestBody = <String, dynamic>{'enabled': enabled};
      if (apiKey != null) requestBody['api_key'] = apiKey;
      final response = await dio.put('/settings/gemini-key', data: requestBody);
      final body = response.data as Map<String, dynamic>;
      setState(() {
        _enabled = body['enabled'] as bool;
        _configured = body['configured'] as bool;
        _apiKeyController.clear();
        _success = 'Saved.';
      });
    } catch (error) {
      setState(() => _error = 'Save failed: $error');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppCardHeader(
            icon: '✨',
            title: 'Gemini AI',
            subtitle: 'Optional cloud assist (chat, AI validation/recovery). The key is encrypted and stored only on this PC.',
          ),
          ?_error != null ? AppAlert(kind: AppAlertKind.error, message: _error!) : null,
          ?_success != null ? AppAlert(kind: AppAlertKind.success, message: _success!) : null,
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Enable Gemini',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
                        Text(
                          _configured ? 'A key is configured on this device.' : 'No key configured yet — enter one below.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    activeThumbColor: AppColors.accent,
                    onChanged: _saving || (!_configured && !_enabled) ? null : (v) => _save(enabled: v),
                  ),
                ],
              ),
            ),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              style: const TextStyle(fontSize: 13, color: AppColors.heading),
              decoration: const InputDecoration(
                labelText: 'Gemini API key',
                hintText: 'Paste a new key to replace the stored one',
                isDense: true,
              ),
              // Rebuilds so the Save button's disabled-when-empty state
              // (below) tracks what's actually typed, not just the last
              // full-widget rebuild.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving || _apiKeyController.text.trim().isEmpty
                    ? null
                    : () => _save(apiKey: _apiKeyController.text.trim(), enabled: true),
                child: Text(_saving ? 'Saving...' : 'Save key'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
