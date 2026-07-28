import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

/// Client-side processing preferences — mirrors the HTML source's
/// `SETTINGS` JS object (localStorage-persisted there). The backend has
/// no settings/config endpoint for these yet, so this is genuinely
/// local-only, persisted to secure storage rather than a server profile.
class AppSettings {
  const AppSettings({
    this.templateLearning = true,
    this.useTemplatesFirst = true,
    this.autoSaveTemplate = true,
    this.ocrCache = true,
    this.aiDetection = true,
    this.imageEnhancement = true,
    this.multiPassOcr = true,
    this.confidenceHighlight = true,
    this.learningMode = true,
    this.correctionLearning = true,
    this.autoApplyLearnedCorrections = true,
    this.automaticValidation = true,
    this.confidenceThreshold = 75,
  });

  final bool templateLearning;
  final bool useTemplatesFirst;
  final bool autoSaveTemplate;
  final bool ocrCache;
  final bool aiDetection;
  final bool imageEnhancement;
  final bool multiPassOcr;
  final bool confidenceHighlight;
  final bool learningMode;
  final bool correctionLearning;
  final bool autoApplyLearnedCorrections;
  final bool automaticValidation;
  final double confidenceThreshold;

  AppSettings copyWith({
    bool? templateLearning,
    bool? useTemplatesFirst,
    bool? autoSaveTemplate,
    bool? ocrCache,
    bool? aiDetection,
    bool? imageEnhancement,
    bool? multiPassOcr,
    bool? confidenceHighlight,
    bool? learningMode,
    bool? correctionLearning,
    bool? autoApplyLearnedCorrections,
    bool? automaticValidation,
    double? confidenceThreshold,
  }) {
    return AppSettings(
      templateLearning: templateLearning ?? this.templateLearning,
      useTemplatesFirst: useTemplatesFirst ?? this.useTemplatesFirst,
      autoSaveTemplate: autoSaveTemplate ?? this.autoSaveTemplate,
      ocrCache: ocrCache ?? this.ocrCache,
      aiDetection: aiDetection ?? this.aiDetection,
      imageEnhancement: imageEnhancement ?? this.imageEnhancement,
      multiPassOcr: multiPassOcr ?? this.multiPassOcr,
      confidenceHighlight: confidenceHighlight ?? this.confidenceHighlight,
      learningMode: learningMode ?? this.learningMode,
      correctionLearning: correctionLearning ?? this.correctionLearning,
      autoApplyLearnedCorrections: autoApplyLearnedCorrections ?? this.autoApplyLearnedCorrections,
      automaticValidation: automaticValidation ?? this.automaticValidation,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
        'templateLearning': templateLearning,
        'useTemplatesFirst': useTemplatesFirst,
        'autoSaveTemplate': autoSaveTemplate,
        'ocrCache': ocrCache,
        'aiDetection': aiDetection,
        'imageEnhancement': imageEnhancement,
        'multiPassOcr': multiPassOcr,
        'confidenceHighlight': confidenceHighlight,
        'learningMode': learningMode,
        'correctionLearning': correctionLearning,
        'autoApplyLearnedCorrections': autoApplyLearnedCorrections,
        'automaticValidation': automaticValidation,
        'confidenceThreshold': confidenceThreshold,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        templateLearning: json['templateLearning'] as bool? ?? true,
        useTemplatesFirst: json['useTemplatesFirst'] as bool? ?? true,
        autoSaveTemplate: json['autoSaveTemplate'] as bool? ?? true,
        ocrCache: json['ocrCache'] as bool? ?? true,
        aiDetection: json['aiDetection'] as bool? ?? true,
        imageEnhancement: json['imageEnhancement'] as bool? ?? true,
        multiPassOcr: json['multiPassOcr'] as bool? ?? true,
        confidenceHighlight: json['confidenceHighlight'] as bool? ?? true,
        learningMode: json['learningMode'] as bool? ?? true,
        correctionLearning: json['correctionLearning'] as bool? ?? true,
        autoApplyLearnedCorrections: json['autoApplyLearnedCorrections'] as bool? ?? true,
        automaticValidation: json['automaticValidation'] as bool? ?? true,
        confidenceThreshold: (json['confidenceThreshold'] as num?)?.toDouble() ?? 75,
      );
}

const _settingsKey = 'app_settings';

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._ref) : super(const AppSettings()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final storage = _ref.read(secureStorageProvider);
    final raw = await storage.read(key: _settingsKey);
    if (raw != null) {
      state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  }

  Future<void> update(AppSettings Function(AppSettings) updater) async {
    state = updater(state);
    final storage = _ref.read(secureStorageProvider);
    await storage.write(key: _settingsKey, value: jsonEncode(state.toJson()));
  }
}

final settingsControllerProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(ref),
);
