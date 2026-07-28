import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';

/// Pixel-accurate migration of the HTML source's Settings modal —
/// rendered as a full screen here rather than a modal, matching this
/// app's screen-per-route navigation instead of the HTML wizard's
/// overlay modals. Every toggle name/default matches the HTML's
/// `SETTINGS` JS object exactly.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
