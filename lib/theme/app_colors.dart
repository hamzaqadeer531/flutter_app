import 'package:flutter/material.dart';

/// Design tokens extracted verbatim from the HTML source of truth
/// (BankWorkingGenerator_Phase3_07-07-2026 FINAL QCR.html, `:root{}` CSS
/// custom properties). Every screen — including ones with no HTML
/// precedent (auth, dashboard, admin, dataset manager) — must build on
/// these exact values so the whole app reads as one product.
class AppColors {
  AppColors._();

  static const Color bodyBackground = Color(0xFF0A0C10);
  static const Color navy = Color(0xFF12151C);
  static const Color panel = Color(0xFF12151C);
  static const Color panel2 = Color(0xFF171B24);
  static const Color gray = Color(0xFF171B24);

  /// Named `--blue` in the HTML source, but it's actually the app's
  /// lime-green accent — kept the HTML's own naming in comments only,
  /// not in code, to avoid confusing future readers.
  static const Color accent = Color(0xFFC7DA2E);
  static const Color accentOn = Color(0xFF0E1116); // `--oncolor`: text color placed on top of accent-filled surfaces
  static Color accentSubtle = accent.withValues(alpha: 0.13); // `--lblue`

  static const Color red = Color(0xFFE4573D);
  static Color redSubtle = red.withValues(alpha: 0.14);

  static const Color green = Color(0xFF7FCB4A);
  static Color greenSubtle = green.withValues(alpha: 0.14);

  static const Color orange = Color(0xFFE0A73E);
  static Color orangeSubtle = orange.withValues(alpha: 0.14);

  static const Color info = Color(0xFF6FB7FF);

  static const Color border = Color(0x1AFFFFFF); // rgba(255,255,255,.10)
  static const Color text = Color(0xFFE8ECF1);
  static Color muted = text.withValues(alpha: 0.55);
  static const Color heading = Color(0xFFEDEFF3);

  static const double radius = 8.0;
  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x73000000), blurRadius: 16, offset: Offset(0, 2)), // 0 2px 16px rgba(0,0,0,.45)
  ];
}
